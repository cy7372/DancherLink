# Icon Updater Tool

This utility script automatically generates all required icon formats for the DancherLink-qt project from a single source image.

## Prerequisites

- Python 3.x
- Pillow library (`pip install Pillow`)

## Usage

1.  Navigate to the project root directory.
2.  Run the script providing the path to your source image (PNG recommended, ideally 1024x1024 or larger).

```bash
python tools/icon_updater/update_icons.py path/to/your/icon.png
```

## What it updates

The script automatically resizes and converts the source image to update the following files:

-   `app/dancherlink.ico`: Windows application icon (contains 256x256, 128x128, 64x64, 48x48, 32x32, 16x16 sizes).
-   `app/dancherlink.icns`: macOS application icon bundle.
-   `app/dancherlink_wix.png`: Installer logo (64x64).
-   `app/deploy/steamlink/dancherlink.png`: Steam Link icon (116x116).
-   `app/res/dancherlink.svg`: Scalable Vector Graphic (wraps a high-res PNG).

## Notes

-   The script assumes it is located in `tools/icon_updater/` and calculates the project root relative to that.
-   If you add new icon targets, please update the `paths` dictionary in `update_icons.py`.
