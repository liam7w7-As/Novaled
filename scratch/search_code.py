import os

def search_text(directory, term):
    results = []
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith('.dart'):
                filepath = os.path.join(root, file)
                try:
                    with open(filepath, 'r', encoding='utf-8') as f:
                        for idx, line in enumerate(f, 1):
                            if term.lower() in line.lower():
                                results.append(f"{filepath}:{idx}: {line.strip()}")
                except Exception as e:
                    pass
    return results

print("=== References to 'clientes' ===")
for r in search_text("lib", "clientes")[:30]:
    print(r)

print("\n=== References to 'Cliente' ===")
for r in search_text("lib", "Cliente")[:30]:
    print(r)
