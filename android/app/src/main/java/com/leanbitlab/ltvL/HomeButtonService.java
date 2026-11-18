/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

package com.omeda.arc;

import android.accessibilityservice.AccessibilityService;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.view.View;
import android.view.WindowManager;
import android.widget.ImageView;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;

/**
 * Google TV opens its own launcher on Home even when another app holds the HOME role, and on TCL
 * sets the key is handled before accessibility key filtering. So this service waits for the stock
 * home screen to come to the front and replaces it with this launcher.
 *
 * Android only switches to this launcher once it has drawn its first frame, which takes seconds on a
 * cold start (after boot), so until then the stock home screen stays visible. On a cold start the
 * service covers it with an overlay showing this launcher's home screen as last seen (black until
 * that picture is loaded, or if there is none), which MainActivity removes when its UI shows, or
 * that goes by itself after {@link #COVER_TIMEOUT_MS}.
 */
public class HomeButtonService extends AccessibilityService {
    static final String STOCK_HOME_PACKAGE = "com.google.android.apps.tv.launcherx";
    static final String STOCK_HOME_ACTIVITY = STOCK_HOME_PACKAGE + ".home.HomeActivity";

    // The active window can still be empty right after connecting (boot, reinstall), so check again.
    private static final long[] CONNECT_CHECK_DELAYS_MS = {0, 1000, 3000};

    // Long enough for a cold start after boot (measured 2.6-5.3 s from the open request to the first
    // frame, and the boot cover starts about 1.5 s before that request), short enough that a
    // launcher that never shows does not leave the screen black.
    private static final long COVER_TIMEOUT_MS = 12_000;

    // After boot the service connects before the stock home screen draws (EarlyStartReceiver keeps
    // the process running), so it covers straight away. Only this soon after boot: a later reconnect
    // (the process restarted while another app plays) must not black out that app.
    private static final long BOOT_COVER_WINDOW_MS = 120_000;

    private static volatile HomeButtonService instance;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable coverTimeout = this::removeCover;
    private View cover;

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        instance = this;
        if (SystemClock.elapsedRealtime() < BOOT_COVER_WINDOW_MS && !MainActivity.isCreated()) {
            showCover();
        }
        for (long delay : CONNECT_CHECK_DELAYS_MS) {
            handler.postDelayed(this::replaceStockHomeIfShowing, delay);
        }
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        if (event.getEventType() != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            return;
        }
        CharSequence className = event.getClassName();
        if (className != null && STOCK_HOME_ACTIVITY.contentEquals(className)) {
            openLauncher();
        }
    }

    /** Covers the stock home screen that was already in front before this service connected. */
    private void replaceStockHomeIfShowing() {
        AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root == null) {
            return;
        }
        CharSequence packageName = root.getPackageName();
        if (packageName != null && STOCK_HOME_PACKAGE.contentEquals(packageName)) {
            openLauncher();
        }
    }

    private void openLauncher() {
        if (!MainActivity.isCreated()) {
            showCover();
        }
        Intent intent = new Intent(this, MainActivity.class)
                .setAction(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_HOME)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
        startActivity(intent);
    }

    private void showCover() {
        if (cover != null) {
            return;
        }
        ImageView view = new ImageView(this);
        view.setBackgroundColor(Color.BLACK);
        view.setScaleType(ImageView.ScaleType.FIT_XY);
        WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                        | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                        | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                        | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.OPAQUE);
        try {
            getSystemService(WindowManager.class).addView(view, params);
        } catch (RuntimeException e) {
            return;
        }
        cover = view;
        handler.postDelayed(coverTimeout, COVER_TIMEOUT_MS);
        String snapshot = MainActivity.homeSnapshotFile(this).getPath();
        new Thread(() -> {
            Bitmap picture = BitmapFactory.decodeFile(snapshot);
            if (picture != null) {
                handler.post(() -> {
                    if (cover == view) {
                        view.setImageBitmap(picture);
                    }
                });
            }
        }, "home-snapshot-load").start();
    }

    private void removeCover() {
        handler.removeCallbacks(coverTimeout);
        if (cover == null) {
            return;
        }
        try {
            getSystemService(WindowManager.class).removeView(cover);
        } catch (RuntimeException ignored) {
        }
        cover = null;
    }

    /** Called by MainActivity once its UI is on screen. */
    static void hideCover() {
        HomeButtonService service = instance;
        if (service != null) {
            service.handler.post(service::removeCover);
        }
    }

    @Override
    public void onInterrupt() {
    }

    @Override
    public void onDestroy() {
        removeCover();
        handler.removeCallbacksAndMessages(null);
        if (instance == this) {
            instance = null;
        }
        super.onDestroy();
    }
}
