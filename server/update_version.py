import json
import sys
import os

# Usage: python update_version.py <version> <arch> <build_config>

def main():
    if len(sys.argv) != 4:
        print("Usage: python update_version.py <version> <arch> <build_config>")
        sys.exit(1)

    version = sys.argv[1]
    arch = sys.argv[2]
    build_config = sys.argv[3]

    # Map arch to JSON arch
    json_arch = "x86_64" if arch == "x64" else arch

    # The updates.json file is expected to be in the same directory as this script
    script_dir = os.path.dirname(os.path.abspath(__file__))
    json_path = os.path.join(script_dir, 'updates.json')

    if not os.path.exists(json_path):
        print(f"Manifest file not found: {json_path}")
        sys.exit(1)

    try:
        with open(json_path, 'r', encoding='utf-8') as f:
            content = f.read().strip()
            if not content:
                # Initialize with empty list if empty
                data = []
            else:
                data = json.loads(content)
    except json.JSONDecodeError as e:
        print(f"Failed to parse JSON from {json_path}: {e}")
        sys.exit(1)

    # Ensure data is a list
    if not isinstance(data, list):
        data = [data]

    found = False
    for entry in data:
        if entry.get('platform') == 'windows' and entry.get('arch') == json_arch:
            entry['version'] = version
            # Preserve the specific URL format requested
            entry['browser_url'] = f"file://cyyu.me/Users/CyYu/Programs/DancherLink-qt/build/build-{arch}-{build_config}/DancherLink.msi"
            found = True
            break

    if not found:
        print(f"Warning: Could not find matching entry in {json_path} for arch {json_arch}")
        # Optionally create it? For now, just warning as per previous logic.
    else:
        with open(json_path, 'w', encoding='utf-8') as f:
            # Always write as a list to maintain the array format required by the application
            json.dump(data, f, indent=4)
        print(f"Updated {json_path} to version {version}")

if __name__ == "__main__":
    main()
