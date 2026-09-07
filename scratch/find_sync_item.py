with open("lib/drive_service.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()

for idx, line in enumerate(lines, 1):
    if "syncItemToDrive" in line:
        print(f"Line {idx}: {line.strip()}")
        # print the next 20 lines
        for j in range(idx, min(idx + 100, len(lines))):
            print(f"  {j+1}: {lines[j].strip()}")
        break
