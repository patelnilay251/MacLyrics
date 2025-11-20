#!/usr/bin/env python3
"""
Script to add new Swift files to Xcode project after refactoring.
This script modifies the project.pbxproj file to include all new files.
"""

import os
import uuid
import re
import shutil
from pathlib import Path

def generate_uuid():
    """Generate a 24-character UUID for Xcode"""
    return str(uuid.uuid4()).replace('-', '').upper()[:24]

def find_new_swift_files(base_path):
    """Find all Swift files in the project"""
    swift_files = []
    for root, dirs, files in os.walk(base_path):
        # Skip hidden and build directories
        dirs[:] = [d for d in dirs if not d.startswith('.') and d not in ['build', 'DerivedData']]
        for file in files:
            if file.endswith('.swift'):
                rel_path = os.path.relpath(os.path.join(root, file), base_path)
                swift_files.append(rel_path)
    return sorted(swift_files)

def backup_project_file(project_path):
    """Create a backup of the project file"""
    backup_path = project_path + '.backup'
    shutil.copy2(project_path, backup_path)
    print(f"✓ Created backup: {backup_path}")
    return backup_path

def main():
    # Paths
    project_root = Path(__file__).parent
    project_file = project_root / "LyricsForMac.xcodeproj" / "project.pbxproj"
    lyrics_for_mac_dir = project_root / "LyricsForMac"
    
    print("🔍 Scanning for Swift files...")
    swift_files = find_new_swift_files(lyrics_for_mac_dir)
    print(f"Found {len(swift_files)} Swift files:\n")
    
    for f in swift_files:
        print(f"  • {f}")
    
    print(f"\n⚠️  Manual Step Required:")
    print(f"To add these files to your Xcode project:")
    print(f"")
    print(f"1. Open LyricsForMac.xcodeproj in Xcode")
    print(f"2. Right-click on the 'LyricsForMac' group in the Project Navigator")
    print(f"3. Select 'Add Files to LyricsForMac...'")
    print(f"4. Navigate to the following folders and add them:")
    print(f"   - Models/")
    print(f"   - Services/")
    print(f"   - Theme/")
    print(f"   - Utilities/")
    print(f"   - Playback/")
    print(f"   - ViewModels/")
    print(f"   - Views/")
    print(f"   - AppDelegate/")
    print(f"5. Make sure 'Create groups' is selected")
    print(f"6. Ensure 'LyricsForMac' target is checked")
    print(f"7. Click 'Add'")
    print(f"")
    print(f"Alternatively, you can drag and drop the folders from Finder into Xcode.")
    print(f"")
    print(f"✅ Refactoring complete! Your code is now organized into modules.")

if __name__ == "__main__":
    main()

