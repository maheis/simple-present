# Privacy Policy for SimplePresent

Last updated: 2026-09-25

## 1. Controller

The person responsible for data processing in connection with SimplePresent is:

- Name/Handle: maheis
- Contact: [maheis](mailto:maheis@heister.be)

## 2. About the app

SimplePresent is a local task, presentation, note, and productivity helper. It is designed to work locally first. Cloud synchronization is optional and is only used if you explicitly configure and pair a sync server.

## 3. What data is processed

The app may store the following data if you enter or create it:

- tasks, task status, ordering, timestamps, notes, subtasks, and reminders
- backlog, done, trash, and related task metadata
- local notes and app state
- app settings such as font, text size, theme mode, colors, backup settings, and cleanup settings
- optional backup and export files
- optional cloud sync configuration such as server URL, account/device identifiers, pairing state, sync status, and encrypted sync payload metadata

Depending on how you use the app, this data may include personal or sensitive information. You decide what you store in the app.

## 4. Local storage

By default, data is stored locally on your device. SimplePresent uses local app storage and local data files/databases depending on the platform and feature.

The app does not send your data to a project-operated cloud by default.

## 5. Optional self-hosted cloud synchronization

SimplePresent is currently the only app in this project family with cloud synchronization support.

Cloud synchronization is optional. It only transmits data to a server that you explicitly choose, configure, and pair with the app. This can be a self-hosted sync server operated by you. The repository contains the server tools and documentation needed for self-hosting.

If cloud synchronization is enabled, sync data is intended to be encrypted on the client before transmission. The server is designed to store opaque encrypted payloads and device/account metadata required for synchronization. The server operator should not need access to your plaintext task data or encryption keys.

You can avoid cloud synchronization entirely by not configuring a sync server.

## 6. Purpose and legal basis

Data is processed solely to provide the app features you use, including task management, reminders, local storage, backup/export, cleanup features, and optional synchronization with a server you choose.

Processing is based on your voluntary use of the app and the necessity of storing data to provide the requested functionality.

## 7. Sharing with third parties

SimplePresent does not automatically share your data with third parties. No analytics, advertising, tracking, or crash-reporting services are integrated by default.

If you export, copy, back up, synchronize, or share data yourself, the privacy terms of the chosen destination, server, or service may also apply.

## 8. Permissions and technical services

The app may use local file access for exports, backups, imports, or desktop/mobile integration features. Optional cloud synchronization requires network access to the server you configure.

Self-hosted server operation is under your control. If you use a server operated by someone else, that operator may process encrypted sync payloads and technical metadata required to provide the service.

## 9. Retention and deletion

Data remains on your device until you delete it in the app, remove the app data, or uninstall the app. Optional cleanup settings can remove completed or trashed items after configured retention periods.

Backup, export, and synchronized copies may remain wherever you stored or synchronized them. You may need to delete those copies separately.

## 10. Security

Local data should be protected by device-level security such as screen lock, disk encryption, and regular backups.

If you enable cloud synchronization, use HTTPS and a trusted server. When self-hosting, keep the server, reverse proxy, TLS certificates, and system packages up to date. Protect configuration files, secrets, device tokens, and backup files.

## 11. Your rights

Subject to applicable law, you may have the right to:

- access your personal data
- correct inaccurate data
- delete your data
- restrict processing
- receive a portable copy of your data

To exercise your rights or ask questions about data processing, contact the controller listed above.

## 12. Changes to this privacy policy

This privacy policy may be updated if the app or its data processing changes. The current version is available in this repository as `PRIVACY.md`.
