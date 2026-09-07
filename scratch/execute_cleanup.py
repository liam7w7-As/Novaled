import json
import sqlite3
import urllib.request
import urllib.parse
import os
import re
import unicodedata
from datetime import datetime

CLIENT_ID = "589557753451-nmud759lvb6gm4froqfs25sbstsm0qhd.apps.googleusercontent.com"
CLIENT_SECRET = "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"
TOKENS_PATH = r"C:\Users\UnseR\AppData\Roaming\com.example\novaled_app\auth_tokens.json"
DB_PATH = r"C:\Users\UnseR\AppData\Roaming\com.example\novaled_app\novaled.db"
ROOT_FOLDER = "1_rV47JiauhIlZasrEeztXz5TUhWPCdXk"
CSV_PATH = r"C:\Almir_trabajos\Novaled Sistema\base de datos\lista de inventario.csv"

def refresh_tokens():
    with open(TOKENS_PATH, "r", encoding="utf-8") as f:
        creds = json.load(f)
    refresh_token = creds.get("refreshToken")
    url = "https://oauth2.googleapis.com/token"
    data = urllib.parse.urlencode({
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "grant_type": "refresh_token",
        "refresh_token": refresh_token
    }).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/x-www-form-urlencoded"})
    with urllib.request.urlopen(req) as response:
        res_data = json.loads(response.read().decode("utf-8"))
        return res_data["access_token"]

def drive_request(url, headers, method="GET", data=None):
    req = urllib.request.Request(url, headers=headers, method=method, data=data)
    with urllib.request.urlopen(req) as response:
        return json.loads(response.read().decode("utf-8"))

def drive_list_files(access_token, query):
    headers = {"Authorization": f"Bearer {access_token}"}
    params = urllib.parse.urlencode({
        "q": query,
        "fields": "files(id, name)",
        "pageSize": 100,
        "supportsAllDrives": "true",
        "includeItemsFromAllDrives": "true"
    })
    url = f"https://www.googleapis.com/drive/v3/files?{params}"
    return drive_request(url, headers).get("files", [])

def drive_delete_file(access_token, file_id):
    headers = {"Authorization": f"Bearer {access_token}"}
    url = f"https://www.googleapis.com/drive/v3/files/{file_id}?supportsAllDrives=true"
    req = urllib.request.Request(url, headers=headers, method="DELETE")
    try:
        req_res = urllib.request.urlopen(req)
        status = req_res.status
        # read content to close connection
        req_res.read()
        return status in (200, 204)
    except Exception as e:
        print(f"  Error deleting file {file_id} from Drive: {e}")
        return False

def upload_index_json(access_token, folder_id, data_list):
    headers = {"Authorization": f"Bearer {access_token}"}
    files = drive_list_files(access_token, f"'{folder_id}' in parents and name='index.json' and trashed=false")
    
    json_bytes = json.dumps(data_list, ensure_ascii=False).encode("utf-8")
    
    if files:
        file_id = files[0]["id"]
        print(f"Updating index.json (ID: {file_id}) on Drive...")
        url = f"https://www.googleapis.com/upload/drive/v3/files/{file_id}?uploadType=media&supportsAllDrives=true"
        req = urllib.request.Request(url, headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json"
        }, method="PATCH", data=json_bytes)
        with urllib.request.urlopen(req) as res:
            res.read()
        return file_id
    else:
        print("Creating index.json on Drive...")
        metadata_url = "https://www.googleapis.com/drive/v3/files?supportsAllDrives=true"
        metadata_headers = {
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json"
        }
        metadata_body = json.dumps({
            "name": "index.json",
            "parents": [folder_id],
            "mimeType": "application/json"
        }).encode("utf-8")
        meta_res = drive_request(metadata_url, metadata_headers, method="POST", data=metadata_body)
        file_id = meta_res["id"]
        
        url = f"https://www.googleapis.com/upload/drive/v3/files/{file_id}?uploadType=media&supportsAllDrives=true"
        req = urllib.request.Request(url, headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json"
        }, method="PATCH", data=json_bytes)
        with urllib.request.urlopen(req) as res:
            res.read()
        return file_id

def clean_text(text):
    if not text:
        return ""
    text = ''.join(c for c in unicodedata.normalize('NFD', text) if unicodedata.category(c) != 'Mn')
    text = re.sub(r'[^a-zA-Z0-9]', '', text).lower()
    return text

def main():
    try:
        print("1. Refreshing Google Drive credentials...")
        access_token = refresh_tokens()
        
        # Parse CSV to obtain the latest price and date for matching
        csv_data = {}
        if os.path.exists(CSV_PATH):
            print("2. Parsing CSV file to verify updated prices/dates...")
            with open(CSV_PATH, 'r', encoding='utf-8-sig', errors='ignore') as f:
                for line in f:
                    parts = line.strip().split(',')
                    if len(parts) >= 4:
                        nombre = parts[0].strip()
                        precio_str = parts[1].strip()
                        date_str = parts[3].strip()
                        
                        cleaned = clean_text(nombre)
                        try:
                            precio = float(precio_str) if precio_str else 0.0
                        except ValueError:
                            precio = 0.0
                        
                        try:
                            date_obj = datetime.strptime(date_str, "%Y/%m/%d")
                        except ValueError:
                            date_obj = datetime.min
                        
                        if cleaned not in csv_data or date_obj > csv_data[cleaned]['date']:
                            csv_data[cleaned] = {
                                'nombre': nombre,
                                'precio': precio,
                                'date_str': date_str,
                                'date': date_obj
                            }
        else:
            print("Warning: original CSV file not found. Accents and fallbacks will be used.")

        # Connect to DB
        print("3. Querying local database articles...")
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT id, nombre, precio, familia, subcategoria, folderId, finalArtId FROM articulos")
        rows = cursor.fetchall()

        # Group by normalized name
        from collections import defaultdict
        grouped = defaultdict(list)
        for r in rows:
            art_id, nombre, precio, familia, subcategoria, folderId, finalArtId = r
            cleaned = clean_text(nombre)
            grouped[cleaned].append({
                'id': art_id,
                'nombre': nombre,
                'precio': precio,
                'familia': familia,
                'subcategoria': subcategoria,
                'folderId': folderId,
                'finalArtId': finalArtId
            })

        duplicates = {k: v for k, v in grouped.items() if len(v) > 1}
        print(f"Found {len(duplicates)} duplicate groups.")

        deletions = []
        
        for key, list_arts in duplicates.items():
            # Selection algorithm
            # 1. Prefer ones with finalArtId
            arts_with_final = [a for a in list_arts if a['finalArtId']]
            if len(arts_with_final) == 1:
                best = arts_with_final[0]
            else:
                csv_match = csv_data.get(key)
                if csv_match:
                    # Look for exact price match or closest name
                    arts_with_csv_price = [a for a in list_arts if abs(a['precio'] - csv_match['precio']) < 0.01]
                    if len(arts_with_csv_price) == 1:
                        best = arts_with_csv_price[0]
                    else:
                        accented = [a for a in list_arts if any(c in a['nombre'] for c in 'áéíóúÁÉÍÓÚñÑ')]
                        if len(accented) == 1:
                            best = accented[0]
                        else:
                            best = max(list_arts, key=lambda x: len(x['nombre']))
                else:
                    accented = [a for a in list_arts if any(c in a['nombre'] for c in 'áéíóúÁÉÍÓÚñÑ')]
                    if len(accented) == 1:
                        best = accented[0]
                    else:
                        best = list_arts[0]
            
            for art in list_arts:
                if art['id'] != best['id']:
                    deletions.append(art)

        print(f"Total rows to delete: {len(deletions)}")
        
        # 4. Perform deletions in local SQLite and Google Drive
        deleted_ids = []
        for i, d in enumerate(deletions, 1):
            art_id = d['id']
            folder_id = d['folderId']
            nombre = d['nombre']
            print(f"[{i}/{len(deletions)}] Cleaning duplicate '{nombre}' (ID: {art_id})")
            
            # Delete from Google Drive if folderId is valid
            if folder_id:
                print(f"  Deleting folder from Google Drive: {folder_id}...")
                success = drive_delete_file(access_token, folder_id)
                if success:
                    print("  Folder successfully deleted from Drive.")
                else:
                    print("  Folder not found or deletion failed on Drive (ignored).")
            
            # Delete from SQLite
            cursor.execute("DELETE FROM articulos WHERE id = ?", (art_id,))
            deleted_ids.append(art_id)
            
        conn.commit()
        print(f"Successfully deleted {len(deleted_ids)} duplicate rows from SQLite.")

        # 5. Query remaining articles to rebuild index.json
        print("5. Rebuilding index.json...")
        cursor.execute("SELECT nombre, precio, precioCaja, descripcion, folderId, finalArtId, proveedor, codCaja, stockJson, familia, subcategoria, unidad, unidadDetalle FROM articulos")
        remaining_rows = cursor.fetchall()
        
        articles_data = []
        for r in remaining_rows:
            art_map = {
                "nombre": r[0],
                "precio": float(r[1]),
                "precioCaja": float(r[2]) if r[2] is not None else 0.0,
                "descripcion": r[3] or "",
                "folderId": r[4],
                "finalArtId": r[5],
                "proveedor": r[6],
                "codCaja": r[7] or "",
                "stockJson": r[8],
                "familia": r[9] or "",
                "subcategoria": r[10] or "",
                "unidad": r[11] or "Unidad",
                "unidadDetalle": r[12] or ""
            }
            articles_data.append(art_map)

        print(f"Remaining unique articles: {len(articles_data)}")

        # 6. Upload regenerated index.json to Google Drive
        print("6. Uploading clean index.json to Drive...")
        # Get ARTICULOS folder
        db_root_folders = drive_list_files(access_token, f"'{ROOT_FOLDER}' in parents and name='NOVALED-BASE-DE-DATOS' and mimeType='application/vnd.google-apps.folder' and trashed=false")
        if db_root_folders:
            db_root_id = db_root_folders[0]["id"]
            articulos_folders = drive_list_files(access_token, f"'{db_root_id}' in parents and name='ARTICULOS' and mimeType='application/vnd.google-apps.folder' and trashed=false")
            if articulos_folders:
                articulos_folder_id = articulos_folders[0]["id"]
                file_id = upload_index_json(access_token, articulos_folder_id, articles_data)
                print(f"Successfully uploaded index.json. File ID: {file_id}")
            else:
                print("Error: ARTICULOS folder not found on Drive.")
        else:
            print("Error: NOVALED-BASE-DE-DATOS folder not found on Drive.")
            
        conn.close()
        print("Cleanup completed successfully!")

    except Exception as e:
        print(f"Error during cleanup execution: {e}")

if __name__ == "__main__":
    main()
