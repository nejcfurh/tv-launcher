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

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Pops with the trimmed label; an empty string means "use the app's own name".
class RenameAppDialog extends StatelessWidget {
  final String initialValue;

  const RenameAppDialog({super.key, required this.initialValue});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    return SimpleDialog(
      insetPadding: const EdgeInsets.only(bottom: 120),
      contentPadding: const EdgeInsets.all(24),
      title: Text(localizations.renameApp),
      children: [
        TextFormField(
          autofocus: true,
          initialValue: initialValue,
          decoration: InputDecoration(
            labelText: localizations.name,
            helperText: localizations.renameAppHint,
          ),
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.sentences,
          onFieldSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
      ],
    );
  }
}
