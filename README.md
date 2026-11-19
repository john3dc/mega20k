# mega20k — Mega Drive / Genesis for the Tang Nano 20K

Play Mega Drive and Genesis games from microSD with HDMI video and stereo audio. Connect an SNES controller through a suitable adapter.

mega20k is based on **MDTang**, nand2mario’s port of Genesis_MiSTer. It uses the **MiST fpgagen** video processor. This Tang Nano 20K port adds the SD game menu and adapts the memory, video output and controller connections to the board. [MDTang](https://github.com/nand2mario/mdtang) · [MiST fpgagen](https://github.com/mist-devel/fpgagen)

## Start playing

Copy your game files to `/megadrive/` on a FAT32 microSD card, for example `/megadrive/Game.md`. Choose the installation method for your board.

**Standalone.** Connect the board over USB and run this command from the download directory. It replaces the current boot core in flash. [Download the standalone bitstream](megadrive20k-standalone.fs?raw=true) · [Install openFPGALoader](https://trabucayre.github.io/openFPGALoader/guide/first-steps.html)

```sh
openFPGALoader -b tangnano20k --write-flash --verify --offset 0 megadrive20k-standalone.fs
```

**Existing Systems menu.** Copy `megadrive20k.bin` to `/cores/megadrive20k.bin` on the card. Hold **SELECT** at power-on and choose **Mega Drive** under **Systems**. [Download the SD package](megadrive20k.bin?raw=true)

With the card inserted, press **A** or **Start** to launch a game. Press **SELECT + Down** to return to the menu.

## 3D-printable case

The **NEStang FPGA-Bluetooth Case** by john3d houses a Tang Nano 20K and an ESP32-WROOM-32 running BlueRetro as a Bluetooth controller adapter. The model page includes the printable parts and controller pinout. [View the case on Printables](https://www.printables.com/model/914685-nestang-fpga-bluetooth-case-nes-videogame)

## Source and license

The FPGA design, menu firmware and upstream sources are in `src/`. Project-specific code is licensed under GPL-3.0-or-later. [Build instructions](src/README.md) · [License](LICENSE) · [Third-party notices](THIRD-PARTY.txt)
