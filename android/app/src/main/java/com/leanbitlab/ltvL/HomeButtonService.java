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
import android.os.Handler;
import android.os.Looper;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;

/**
 * Google TV opens its own launcher on Home even when another app holds the HOME role, and on TCL
 * sets the key is handled before accessibility key filtering. So this service waits for the stock
 * home screen to come to the front and replaces it with this launcher.
 */
public class HomeButtonService extends AccessibilityService {
    static final String STOCK_HOME_PACKAGE = "com.google.android.apps.tv.launcherx";
    static final String STOCK_HOME_ACTIVITY = STOCK_HOME_PACKAGE + ".home.HomeActivity";

    // The active window can still be empty right after connecting (boot, reinstall), and at boot the
    // stock home screen comes up without an event this service sees. Checking often keeps the time
    // it shows short.
    private static final long CONNECT_CHECK_INTERVAL_MS = 100;
    private static final long CONNECT_CHECK_DURATION_MS = 5000;

    private final Handler handler = new Handler(Looper.getMainLooper());

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        for (long delay = 0; delay <= CONNECT_CHECK_DURATION_MS; delay += CONNECT_CHECK_INTERVAL_MS) {
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
            handler.removeCallbacksAndMessages(null);
            openLauncher();
        }
    }

    private void openLauncher() {
        Intent intent = new Intent(this, MainActivity.class)
                .setAction(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_HOME)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
        startActivity(intent);
    }

    @Override
    public void onInterrupt() {
    }

    @Override
    public void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        super.onDestroy();
    }
}
