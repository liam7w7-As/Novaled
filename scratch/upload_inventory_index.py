import json
import sqlite3
import urllib.request
import urllib.parse
import os

CLIENT_ID = "589557753451-nmud759lvb6gm4froqfs25sbstsm0qhd.apps.googleusercontent.com"
CLIENT_SECRET = "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"
TOKENS_PATH = r"C:\Users\UnseR\AppData\Roaming\com.example\novaled_app\auth_tokens.json"
DB_PATH = r"C:\Users\UnseR\AppData\Roaming\com.example\novaled_app\novaled.db"
ROOT_FOLDER = "1_rV47JiauhIlZasrEeztXz5TUhWPCdXk"

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

def drive_create_folder(access_token, name, parent_id):
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json"
    }
    url = "https://www.googleapis.com/drive/v3/files?supportsAllDrives=true"
    body = json.dumps({
        "name": name,
        "mimeType": "application/vnd.google-apps.folder",
        "parents": [parent_id]
    }).encode("utf-8")
    return drive_request(url, headers, method="POST", data=body)

def upload_index_json(access_token, folder_id, data_list):
    headers = {"Authorization": f"Bearer {access_token}"}
    # Check if index.json already exists
    files = drive_list_files(access_token, f"'{folder_id}' in parents and name='index.json' and trashed=false")
    
    json_bytes = json.dumps(data_list, ensure_ascii=False).encode("utf-8")
    
    if files:
        file_id = files[0]["id"]
        print(f"Updating existing index.json (ID: {file_id}) on Drive...")
        url = f"https://www.googleapis.com/upload/drive/v3/files/{file_id}?uploadType=media&supportsAllDrives=true"
        req = urllib.request.Request(url, headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json"
        }, method="PATCH", data=json_bytes)
        with urllib.request.urlopen(req) as res:
            pass
        return file_id
    else:
        print("Creating new index.json on Drive...")
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
        
        # Upload content
        url = f"https://www.googleapis.com/upload/drive/v3/files/{file_id}?uploadType=media&supportsAllDrives=true"
        req = urllib.request.Request(url, headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json"
        }, method="PATCH", data=json_bytes)
        with urllib.request.urlopen(req) as res:
            pass
        return file_id

def main():
    try:
        print("Refreshing Google Drive API token...")
        access_token = refresh_tokens()
        
        # 1. Get NOVALED-BASE-DE-DATOS
        db_root_folders = drive_list_files(access_token, f"'{ROOT_FOLDER}' in parents and name='NOVALED-BASE-DE-DATOS' and mimeType='application/vnd.google-apps.folder' and trashed=false")
        if not db_root_folders:
            print("Error: NOVALED-BASE-DE-DATOS folder not found.")
            return
        db_root_id = db_root_folders[0]["id"]
        
        # 2. Get ARTICULOS
        articulos_folders = drive_list_files(access_token, f"'{db_root_id}' in parents and name='ARTICULOS' and mimeType='application/vnd.google-apps.folder' and trashed=false")
        if not articulos_folders:
            print("Error: ARTICULOS folder not found.")
            return
        articulos_folder_id = articulos_folders[0]["id"]
        
        # 3. Query all articles from SQLite
        print(f"Connecting to SQLite: {DB_PATH}")
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM articulos")
        rows = [dict(r) for r in cursor.fetchall()]
        print(f"Queried {len(rows)} articles from local database.")
        
        if not rows:
            print("No articles to write to index.")
            conn.close()
            return
            
        # 4. Generate JSON array list
        articles_data = []
        for r in rows:
            art_map = {
                "nombre": r["nombre"],
                "precio": float(r["precio"]),
                "precioCaja": float(r["precioCaja"]) if r["precioCaja"] is not None else 0.0,
                "descripcion": r["descripcion"] or "",
                "folderId": r["folderId"],
                "finalArtId": r["finalArtId"],
                "proveedor": r["proveedor"],
                "codCaja": r["codCaja"] or "",
                "stockJson": r["stockJson"],
                "familia": r["familia"] or "",
                "subcategoria": r["subcategoria"] or "",
                "unidad": r["unidad"] or "Unidad",
                "unidadDetalle": r["unidadDetalle"] or ""
            }
            articles_data.append(art_map)
            
        # 5. Upload index.json to Google Drive
        file_id = upload_index_json(access_token, articulos_folder_id, articles_data)
        print(f"Successfully uploaded index.json for articles. File ID: {file_id}")
        conn.close()
        
    except Exception as e:
        print(f"Error generating/uploading index.json: {e}")

if __name__ == "__main__":
    main()
