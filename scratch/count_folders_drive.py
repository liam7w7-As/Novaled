import json
import urllib.request
import urllib.parse

CLIENT_ID = "589557753451-nmud759lvb6gm4froqfs25sbstsm0qhd.apps.googleusercontent.com"
CLIENT_SECRET = "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"
TOKENS_PATH = r"C:\Users\UnseR\AppData\Roaming\com.example\novaled_app\auth_tokens.json"
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

def drive_request(url, headers):
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as response:
        return json.loads(response.read().decode("utf-8"))

def drive_list_files(access_token, query):
    headers = {"Authorization": f"Bearer {access_token}"}
    files = []
    page_token = None
    while True:
        params = {
            "q": query,
            "fields": "nextPageToken, files(id, name)",
            "pageSize": 1000,
            "supportsAllDrives": "true",
            "includeItemsFromAllDrives": "true"
        }
        if page_token:
            params["pageToken"] = page_token
        url = f"https://www.googleapis.com/drive/v3/files?{urllib.parse.urlencode(params)}"
        res = drive_request(url, headers)
        files.extend(res.get("files", []))
        page_token = res.get("nextPageToken")
        if not page_token:
            break
    return files

def main():
    access_token = refresh_tokens()
    
    # 1. Get NOVALED-BASE-DE-DATOS
    db_root_folders = drive_list_files(access_token, f"'{ROOT_FOLDER}' in parents and name='NOVALED-BASE-DE-DATOS' and mimeType='application/vnd.google-apps.folder' and trashed=false")
    if not db_root_folders:
        print("NOVALED-BASE-DE-DATOS folder not found.")
        return
    db_root_id = db_root_folders[0]["id"]
    
    # 2. Get ARTICULOS
    articulos_folders = drive_list_files(access_token, f"'{db_root_id}' in parents and name='ARTICULOS' and mimeType='application/vnd.google-apps.folder' and trashed=false")
    if not articulos_folders:
        print("ARTICULOS folder not found.")
        return
    articulos_folder_id = articulos_folders[0]["id"]
    
    # 3. List all files/folders under ARTICULOS
    folders = drive_list_files(access_token, f"'{articulos_folder_id}' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false")
    print(f"Total folders under ARTICULOS: {len(folders)}")
    
    # 4. List data.json files under ARTICULOS to see how many were synced
    all_files = drive_list_files(access_token, f"name='data.json' and trashed=false")
    print(f"Total data.json files in entire Drive: {len(all_files)}")
    
    # 5. Let's see how many folders have data.json under ARTICULOS
    # Let's count files inside first 5 folders
    print("\nFirst 5 folders under ARTICULOS:")
    for f in folders[:5]:
        contents = drive_list_files(access_token, f"'{f['id']}' in parents and trashed=false")
        print(f"  Folder: '{f['name']}' (ID: {f['id']}) contains: {[c['name'] for c in contents]}")

if __name__ == "__main__":
    main()
