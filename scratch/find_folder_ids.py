with open("lib/drive_service.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()

for idx, line in enumerate(lines, 1):
    if "_getFolderIdForTable" in line or "FolderId" in line:
        print(f"Line {idx}: {line.strip()}")
        # print the next 30 lines
        for j in range(idx, min(idx + 40, len(lines))):
            print(f"  {j+1}: {lines[j].strip()}")
        break
