# Physical Android phone: test checklist

Physical-device testing has **not** been done yet; it needs a real phone. Record results here and in the report (§7.3). Never substitute emulator screenshots.

## 1. Prepare the phone
1. Settings → About phone → tap **Build number** 7 times → Developer options → enable **USB debugging**.
2. Connect by USB and accept the "Allow USB debugging" prompt on the phone.
3. Check that it's detected (PowerShell):
   ```powershell
   & "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" devices
   ```
   The phone must show as `device`, not `unauthorized`.

## 2. Install the APK (no keys or passwords needed)
The release APK is already built (demo mode, bundled official data):
```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install -r <repo>\app\build\app\outputs\flutter-apk\app-release.apk
```
Alternatively, copy the APK to the phone and open it (allow "Install unknown apps" for your file manager). To rebuild it: `cd <repo>\app; flutter build apk --release`.
The phone build uses demo data and a demo profile, so there is no sign-in. Live sign-in needs a configured Firebase project (DEPLOYMENT.md §3); the local emulator mode doesn't work on a phone.

## 3. Capture evidence
- Screenshot on the phone (power + volume down), or from the PC:
  ```powershell
  & "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" exec-out screencap -p > ..\docs\screenshots\phone_01_home.png
  ```
- Name files `phone_NN_<what>.png` and note the phone model and Android version below.

## 4. Checklist
| # | Check | Expected | Result | Screenshot |
|---|---|---|---|---|
| 1 | Install + launch | App opens, no crash; demo or test banner visible as appropriate | | |
| 2 | Registration form (live) or profile setup (demo) | Errors appear only on touched fields; empty submit lists required fields; invalid SAP ID / roll number rejected | | |
| 3 | Keyboard behaviour | Correct keyboard per field (numeric SAP ID, email keyboard); fields scroll above the keyboard | | |
| 4 | Division and batch selection | Div B vs Div C give different timetables (e.g. Tue: Div B labs vs Div C CR 401 lectures) | | |
| 5 | Timetable day/week | Correct subjects, rooms, faculty; breaks shown as free periods | | |
| 6 | Exams | CE exams OR 17 Nov, AI 19 Nov, SE 23 Nov, OS 25 Nov, IVP 27 Nov (10:00–1:00); elective exam appears after choosing an elective | | |
| 7 | Rooms explorer | Floors LG–8 including Floor 2; rooms without classes show "No class listed (unverified)", never "free" | | |
| 8 | Announcements and links | Empty state (no announcements are published in seed data); if a test announcement is published, its link opens in the browser | | |
| 9 | Offline | Airplane mode → reopen → cached data with offline banner (live mode) | | |
| 10 | Notifications | Enabling class reminders asks for permission; "Don't allow" shows the explanation; allowing schedules reminders | | |
| 11 | Screen size / rotation / large text | No overflow on the phone's screen; Settings → Text size 140% stays usable | | |
| 12 | Campus screen | Buildings respond to taps and open the right tab | | |
| 13 | Virtual campus journey | Campus → Academic Block → floor 4 → CR 402 status → floor 7 → Enter library → desk → character sits | | |
| 14 | Focus session | Start 15 min → Pause (time freezes) → Resume → background 1 min → reopen: time still correct | | |
| 15 | Back navigation | System back from Library → Academic Block → Campus; nothing gets stuck | | |
| 16 | **Focus-completion notification** | See §5 | | |

## 5. Verifying the focus-completion notification (reliably)
Android delivers these reminders as *inexact* alarms, typically 0–10 min after the due time. Opening the app before the alarm fires completes the session in-app and correctly cancels the alarm, which is why this wasn't observed on the emulator.
1. Me → turn **Class reminders** on once and tap **Allow**. This grants the notification permission; you can turn class reminders off again.
2. Library → choose a desk → **15 min** → Start. Note the time.
3. Press Home and lock the phone. **Don't open CampusSync again** until the notification appears or 15 + 15 minutes have passed.
4. Result: **Pass** if "Focus session complete" appears (screenshot the shade, note the time). **Fail** if nothing appears 30 min after starting, with permission granted and battery saver off. Record the phone model and Android version.


Phone model / Android version: ____________  Tested by: ____________  Date: ____________
