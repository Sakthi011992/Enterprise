# POS print agent

A small Node 20 program that runs on a computer on the outlet's network (a mini PC or the bar tablet's host). It asks the POS server for print jobs every 2 seconds and sends them to network (LAN) receipt and kitchen printers on port 9100.

## Setup

1. In the POS, go to **Settings → Devices → Register device**. Choose type **PRINTER** and the outlet. Copy the device key. It is shown once.
2. In **Settings → Hardware**, add each printer with its IP address, paper width (58 or 80 mm) and role (receipt printers take bills, X/Z reports and the cash drawer). Set the station routes (BAR → bar printer, KITCHEN → kitchen printer).
3. On the agent computer, install Node.js 20 or later and build:

   ```sh
   cd print-agent
   npm install
   npm run build
   ```

4. Start it with the server URL and device key:

   ```sh
   API_BASE_URL=https://pos.example.com/api/v1 DEVICE_KEY=<key> npm start
   ```

5. Press **Test** on a printer in Settings → Hardware. A test page should print within a few seconds.

## Notes

- Text is sent as 7-bit ASCII. Characters outside ASCII print as `?`. Tamil or other scripts need the printer's code page set up separately (gap, see the Phase 2 report).
- Printers are reached over TCP port 9100 with a 5 second timeout. A failed job is retried by the server up to 3 times, and a ticket moves to the station's fallback printer when one is set.
- The cash drawer pulse is sent through the receipt printer's drawer port (`ESC p 0 25 250`).
