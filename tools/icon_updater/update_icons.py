import os
import sys
import base64
from PIL import Image

def update_icons(source_path, project_root):
    if not os.path.exists(source_path):
        print(f"Error: Source image {source_path} not found.")
        return

    try:
        img = Image.open(source_path)
        img = img.convert("RGBA")
    except Exception as e:
        print(f"Error opening source image: {e}")
        return

    print(f"Loaded source image: {source_path} size={img.size}")

    # Define paths relative to project root
    paths = {
        "ico": os.path.join(project_root, "app", "dancherlink.ico"),
        "icns": os.path.join(project_root, "app", "dancherlink.icns"),
        "wix_png": os.path.join(project_root, "app", "dancherlink_wix.png"),
        "steam_png": os.path.join(project_root, "app", "deploy", "steamlink", "dancherlink.png"),
        "svg": os.path.join(project_root, "app", "res", "dancherlink.svg"),
    }

    # 1. Update app/dancherlink.ico
    try:
        # Standard Windows icon sizes
        icon_sizes = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)]
        img.save(paths["ico"], format="ICO", sizes=icon_sizes)
        print(f"Updated {paths['ico']}")
    except Exception as e:
        print(f"Failed to update {paths['ico']}: {e}")

    # 2. Update app/dancherlink.icns
    try:
        # Save as ICNS. Pillow supports this.
        # Ideally we provide multiple sizes, but Pillow's save(format='ICNS') often handles basic scaling if not provided.
        # For better quality, we can construct an iconset, but simple save is often sufficient for a helper script.
        # If specific sizes are needed, we can create a temporary iconset directory and use iconutil (macOS only)
        # or rely on Pillow's internal handling.
        img.save(paths["icns"], format="ICNS")
        print(f"Updated {paths['icns']}")
    except Exception as e:
        print(f"Failed to update {paths['icns']}: {e}")

    # 3. Update app/dancherlink_wix.png (Installer Logo)
    # Typically 64x64 or similar small size for WiX UI
    try:
        wix_size = (64, 64)
        resized_wix = img.resize(wix_size, Image.Resampling.LANCZOS)
        resized_wix.save(paths["wix_png"])
        print(f"Updated {paths['wix_png']} with size {wix_size}")
    except Exception as e:
        print(f"Failed to update {paths['wix_png']}: {e}")

    # 4. Update app/deploy/steamlink/dancherlink.png
    # Typically 116x116 or similar
    try:
        steam_size = (116, 116)
        resized_steam = img.resize(steam_size, Image.Resampling.LANCZOS)
        resized_steam.save(paths["steam_png"])
        print(f"Updated {paths['steam_png']} with size {steam_size}")
    except Exception as e:
        print(f"Failed to update {paths['steam_png']}: {e}")

    # 5. Update app/res/dancherlink.svg (Embedded PNG)
    try:
        # Resize to 512x512 for vector embedding
        svg_size = (512, 512)
        resized_for_svg = img.resize(svg_size, Image.Resampling.LANCZOS)
        
        # Save to bytes
        from io import BytesIO
        buffered = BytesIO()
        resized_for_svg.save(buffered, format="PNG")
        img_str = base64.b64encode(buffered.getvalue()).decode("utf-8")
        
        svg_content = f'''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{svg_size[0]}" height="{svg_size[1]}" viewBox="0 0 {svg_size[0]} {svg_size[1]}">
    <image width="{svg_size[0]}" height="{svg_size[1]}" xlink:href="data:image/png;base64,{img_str}"/>
</svg>'''
        
        with open(paths["svg"], "w", encoding="utf-8") as f:
            f.write(svg_content)
        print(f"Updated {paths['svg']} (embedded PNG)")
    except Exception as e:
        print(f"Failed to update {paths['svg']}: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python update_icons.py <path_to_source_image>")
        print("Example: python update_icons.py ../../DancherLink.png")
        sys.exit(1)

    source_img = sys.argv[1]
    # Assume script is in tools/icon_updater, so project root is two levels up
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(os.path.dirname(script_dir))
    
    print(f"Project root: {project_root}")
    update_icons(source_img, project_root)
