with open("lib/drive_service.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()

found = False
for idx, line in enumerate(lines, 1):
    if "Future<String?> _getFolderIdForTable(" in line:
        found = True
        print(f"Line {idx}: {line.strip()}")
        # print the next 50 lines
        for j in range(idx, min(idx + 50, len(lines))):
            print(f"  {j+1}: {lines[j].strip()}")
        break
if not found:
    print("Function _getFolderIdForTable not found!")
