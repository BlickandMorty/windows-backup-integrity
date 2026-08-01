# Windows Backup Integrity

Create versioned backups of selected Windows project/state folders, generate SHA-256 manifests, verify readable archives, and restore into a safe staging destination without overwriting a live profile.

This project generalizes the canonical Laptop-Polish publication scripts and the Codex-state backup/restore work that exposed two common failure modes: hardcoded old profile paths and attempts to overwrite files held open by the running app.

## Principles

- Backup, verification, and restore are separate steps.
- Source paths use environment variables instead of a fixed username.
- Backups receive timestamps and never overwrite an earlier run.
- Every file is recorded with relative path, byte count, last-write time, and SHA-256.
- ZIP readability and manifest verification are both required.
- Restore defaults to a new staging directory.
- A live destination is never overwritten by this project.
- Backups containing app state may contain credentials or personal data; never publish them to GitHub.

## Usage

Edit `config/backup.example.json`, then audit:

```powershell
.\src\Backup-State.ps1 -ConfigPath .\config\backup.example.json
```

Create the backup:

```powershell
.\src\Backup-State.ps1 -ConfigPath .\config\backup.example.json -Mode Backup -Apply
```

Verify a directory or ZIP:

```powershell
.\src\Verify-Backup.ps1 -BackupPath D:\Backups\MyBackup.zip
```

Restore into a new empty staging destination:

```powershell
.\src\Restore-ToStaging.ps1 `
  -BackupPath D:\Backups\MyBackup.zip `
  -Destination C:\Users\me\Documents\Restored-State `
  -Apply
```

Close applications before manually replacing their live state. The staging workflow is intentional: it makes profile-path migration and locked-file issues visible before any cutover.

## License

MIT.

