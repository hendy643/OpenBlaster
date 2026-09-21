# HRIR files

HeSuVi impulse responses (WAV, 14 channels at 48 kHz, or 7 channels) and SOFA files for OpenBlaster's virtual
surround. `scripts/install.sh` and `scripts/package.sh` put everything in this directory (subfolders included)
under `/usr/share/openblaster/hrtf`; the app lists each file as an effect on its Virtual surround page. Names
matter for the label: `atmos`, `cmss_game`, `dtshx`, `sbx33` ... (see `profileLabel` in
`app/lib/src/hw/virtual_surround.dart`).

They are recordings of other companies' processing (Dolby, DTS, Creative, Razer, Aureal, Valve's Steam Audio),
collected in the HRTF Database (https://airtable.com/appayGNkn3nSuXkaz/shruimhjdSakUPg2m/tbloLjoZKWJDnLtTc).
Their rights belong to their owners and they are **not** covered by this project's Apache-2.0 licence.
