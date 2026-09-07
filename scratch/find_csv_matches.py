import os
import re
import unicodedata

csv_path = r"C:\Almir_trabajos\Novaled Sistema\base de datos\lista de inventario.csv"
if not os.path.exists(csv_path):
    print("CSV not found.")
    exit(1)

def clean_text(text):
    if not text:
        return ""
    text = ''.join(c for c in unicodedata.normalize('NFD', text) if unicodedata.category(c) != 'Mn')
    text = re.sub(r'[^a-zA-Z0-9]', '', text).lower()
    return text

# The 19 duplicate keys we found
keys_to_find = {
    'bateria9v', 'bateriade9v', 'cablebipolarn10', 'cableutpcat6purocobremetro',
    'detectordeenergiaelectricaunit', 'focoledbotellonde18w', 'focolede2722wluzcalida',
    'focosledahorradoresde25wattsluzblancabombillamarcafideli', 'interruptorsimplemrthree',
    'luminariapublica150wconbrazometalico', 'panelled6060cmsobrepuesto', 'panelledsobrepuesto12w',
    'reflectorled50w', 'termicobipolar20a', 'termicobipolar32a', 'termicobipolar40a',
    'timbreinalambricosimple', 'tuboled20w', 'tuboledde18wluzblanca'
}

with open(csv_path, 'r', encoding='utf-8-sig', errors='ignore') as f:
    for line in f:
        parts = line.strip().split(',')
        if len(parts) > 0:
            name = parts[0]
            cleaned = clean_text(name)
            if cleaned in keys_to_find:
                print(f"CSV line: {line.strip()}")
