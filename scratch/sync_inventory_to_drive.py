import json
import sqlite3
import urllib.request
import urllib.parse
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
import threading

CLIENT_ID = "589557753451-nmud759lvb6gm4froqfs25sbstsm0qhd.apps.googleusercontent.com"
CLIENT_SECRET = "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"
TOKENS_PATH = r"C:\Users\UnseR\AppData\Roaming\com.example\novaled_app\auth_tokens.json"
DB_PATH = r"C:\Users\UnseR\AppData\Roaming\com.example\novaled_app\novaled.db"
ROOT_FOLDER = "1_rV47JiauhIlZasrEeztXz5TUhWPCdXk"

# Global lock for thread-safe access to drive cache
cache_lock = threading.Lock()
drive_cache = {}

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

def drive_list_files(access_token, query, fields="files(id, name, mimeType)"):
    headers = {"Authorization": f"Bearer {access_token}"}
    params = urllib.parse.urlencode({
        "q": query,
        "fields": fields,
        "pageSize": 1000,
        "supportsAllDrives": "true",
        "includeItemsFromAllDrives": "true"
    })
    url = f"https://www.googleapis.com/drive/v3/files?{params}"
    return drive_request(url, headers).get("files", [])

def drive_list_files_paginated(access_token, query, fields="files(id, name, mimeType)"):
    headers = {"Authorization": f"Bearer {access_token}"}
    files = []
    page_token = None
    while True:
        params = {
            "q": query,
            "fields": f"nextPageToken, {fields}",
            "pageSize": 1000,
            "supportsAllDrives": "true",
            "includeItemsFromAllDrives": "true"
        }
        if page_token:
            params["pageToken"] = page_token
        url = f"https://www.googleapis.com/drive/v3/files?{urllib.parse.urlencode(params)}"
        try:
            res = drive_request(url, headers)
            files.extend(res.get("files", []))
            page_token = res.get("nextPageToken")
            if not page_token:
                break
        except Exception as e:
            print(f"Error list files page: {e}")
            break
    return files

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

def drive_create_or_update_data_json(access_token, folder_id, art_data):
    # Check if data.json already exists in folder
    headers = {"Authorization": f"Bearer {access_token}"}
    files = drive_list_files(access_token, f"'{folder_id}' in parents and name='data.json' and trashed=false")
    
    json_bytes = json.dumps(art_data, ensure_ascii=False).encode("utf-8")
    
    if files:
        file_id = files[0]["id"]
        # Update content (Media upload for update)
        url = f"https://www.googleapis.com/upload/drive/v3/files/{file_id}?uploadType=media&supportsAllDrives=true"
        req = urllib.request.Request(url, headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json"
        }, method="PATCH", data=json_bytes)
        with urllib.request.urlopen(req) as res:
            pass
        return file_id
    else:
        # Create file
        metadata_url = "https://www.googleapis.com/drive/v3/files?supportsAllDrives=true"
        metadata_headers = {
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json"
        }
        metadata_body = json.dumps({
            "name": "data.json",
            "parents": [folder_id],
            "mimeType": "application/json"
        }).encode("utf-8")
        meta_res = drive_request(metadata_url, metadata_headers, method="POST", data=metadata_body)
        file_id = meta_res["id"]
        
        # Update media content
        url = f"https://www.googleapis.com/upload/drive/v3/files/{file_id}?uploadType=media&supportsAllDrives=true"
        req = urllib.request.Request(url, headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json"
        }, method="PATCH", data=json_bytes)
        with urllib.request.urlopen(req) as res:
            pass
        return file_id

def sync_single_articulo(access_token, articulos_folder_id, art_dict, idx, total_count):
    art_id = art_dict["id"]
    name = art_dict["nombre"].strip()
    clean_name = name.lower().strip()
    folder_id = art_dict.get("folderId")
    
    # Remove local ID for Drive data.json
    del art_dict["id"]
    
    # Simple retry mechanism for network stability
    retries = 3
    for attempt in range(retries):
        try:
            # 1. Thread-safe cache check
            with cache_lock:
                if clean_name in drive_cache:
                    folder_id = drive_cache[clean_name]
                    
            # 2. If not in cache and not set locally, create a folder on Drive
            if not folder_id:
                print(f"[{idx}/{total_count}] Creating folder on Drive for: {name}...")
                res_folder = drive_create_folder(access_token, name, articulos_folder_id)
                folder_id = res_folder["id"]
                # Thread-safe cache update
                with cache_lock:
                    drive_cache[clean_name] = folder_id
                    
            art_dict["folderId"] = folder_id
            
            # 3. Upload or update data.json inside product folder
            print(f"[{idx}/{total_count}] Syncing data.json for: {name}...")
            drive_create_or_update_data_json(access_token, folder_id, art_dict)
            
            return art_id, folder_id
        except Exception as e:
            if attempt == retries - 1:
                print(f"[{idx}/{total_count}] Final Error syncing '{name}': {e}")
                return art_id, None
            else:
                print(f"[{idx}/{total_count}] Error syncing '{name}', retrying... ({e})")
                time.sleep(1 + attempt)

def main():
    try:
        print("Refreshing Google Drive API access token...")
        access_token = refresh_tokens()
        
        # 1. Get or create NOVALED-BASE-DE-DATOS
        print("Checking base database folder...")
        db_root_folders = drive_list_files(access_token, f"'{ROOT_FOLDER}' in parents and name='NOVALED-BASE-DE-DATOS' and mimeType='application/vnd.google-apps.folder' and trashed=false")
        if db_root_folders:
            db_root_id = db_root_folders[0]["id"]
        else:
            print("Creating NOVALED-BASE-DE-DATOS folder...")
            db_root_id = drive_create_folder(access_token, "NOVALED-BASE-DE-DATOS", ROOT_FOLDER)["id"]
            
        # 2. Get or create ARTICULOS
        print("Checking ARTICULOS folder...")
        articulos_folders = drive_list_files(access_token, f"'{db_root_id}' in parents and name='ARTICULOS' and mimeType='application/vnd.google-apps.folder' and trashed=false")
        if articulos_folders:
            articulos_folder_id = articulos_folders[0]["id"]
        else:
            print("Creating ARTICULOS folder...")
            articulos_folder_id = drive_create_folder(access_token, "ARTICULOS", db_root_id)["id"]
            
        # 3. Retrieve all existing folders under ARTICULOS on Drive to build a cache (paginated!)
        print("Caching existing folders from Google Drive (paginated)...")
        existing_drive_folders = drive_list_files_paginated(access_token, f"'{articulos_folder_id}' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false")
        
        global drive_cache
        drive_cache = {f["name"].lower().strip(): f["id"] for f in existing_drive_folders}
        print(f"Cached {len(drive_cache)} folders from Google Drive.")
        
        # 4. Connect to SQLite database
        print(f"Connecting to SQLite: {DB_PATH}")
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        # We only need to sync articles that don't have folderId, or all articles?
        # Typically sync items that don't have a folderId to save API calls, but let's read the whole table first
        cursor.execute("SELECT * FROM articulos WHERE folderId IS NULL OR folderId = ''")
        local_articulos = [dict(c) for c in cursor.fetchall()]
        print(f"Found {len(local_articulos)} articles in SQLite database that need syncing.")
        
        if not local_articulos:
            print("No articles need synchronization to Google Drive.")
            conn.close()
            return

        # 5. Run sync in parallel using ThreadPoolExecutor
        print("Starting parallel sync on Google Drive...")
        results = []
        with ThreadPoolExecutor(max_workers=10) as executor:
            futures = {
                executor.submit(sync_single_articulo, access_token, articulos_folder_id, art, idx, len(local_articulos)): art
                for idx, art in enumerate(local_articulos, 1)
            }
            
            for future in as_completed(futures):
                art_id, folder_id = future.result()
                if folder_id:
                    results.append((folder_id, art_id))
                    
        # 6. Apply all database updates in a single batch transaction to avoid database locks
        print(f"Writing {len(results)} folder ID updates back to local SQLite database...")
        cursor.executemany("UPDATE articulos SET folderId = ? WHERE id = ?", results)
        conn.commit()
        conn.close()
        
        print("\n--- Parallel Sync Summary ---")
        print(f"Total synchronized articles: {len(results)}")
        print("Google Drive parallel synchronization completed successfully.")
        
    except Exception as e:
        print(f"Error in sync_inventory_to_drive: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
