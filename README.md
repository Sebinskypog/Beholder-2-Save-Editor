# Beholder 2 Save Editor

## What is it?
A save editor for **Beholder 2**.  
It allows you to view and modify in-game variables (like state points) directly in your save files.  

---

## ⚙️ How it works
- Beholder 2 saves have two files: a `.data` (zip with JSON content) and a `.bin` (checksum).  
- The editor:
  1. Opens the `.data` save,
  2. Lets you choose and change a variable,
  3. Automatically recalculates the `.bin` CRC so the game accepts the modified save.  
- Written in PowerShell. Runs locally. No internet connection, no system file changes.

---

## Usage
1. Download `Beholder2SaveEditor.ps1` from this repository.  
2. Place it in your save folder:  `Documents\Warm Lamp Games\Beholder 2\Saves`
3. Create a **desktop shortcut**:
- Right-click the script → **Create shortcut**.  
- Right-click the shortcut → **Properties**.  
- In **Target**, set:
  ```
  C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\<YourName>\Documents\Warm Lamp Games\Beholder 2\Saves\Beholder2SaveEditor.ps1"
  ```
- In **Start in**, set:
  ```
  C:\Users\<YourName>\Documents\Warm Lamp Games\Beholder 2\Saves
  ```

  **!!! Make sure to modify the path accordingly, in `<YourName>` you should add your user. !!!**
  
4. Double-click the shortcut to launch the editor.  
5. Pick a save file, select a variable, and enter the new value.  
6. Launch the game and load your modified save.

---

## Safety
- Always **back up your saves** before editing.  
- This script only edits local save files — it does **not** connect to the internet or require admin rights.  
- VirusTotal scan of the script [here](https://www.virustotal.com/gui/file/d4db5792fec4d5aadb7bcd9d4ca7532019302d7b2cfe3dd988ce6a88c969a635/detection).

---

## License
This project is licensed under the **GNU GPL v3**. 
