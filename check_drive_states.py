import json
import urllib.request
import urllib.parse
import os
from datetime import datetime, timedelta

CLIENT_ID = "589557753451-nmud759lvb6gm4froqfs25sbstsm0qhd.apps.googleusercontent.com"
CLIENT_SECRET = "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"
TOKENS_PATH = r"C:\Users\UnseR\AppData\Roaming\com.example\novaled_app\auth_tokens.json"

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

def drive_list_files(access_token, query, fields="files(id, name, mimeType, parents)"):
    headers = {"Authorization": f"Bearer {access_token}"}
    params = urllib.parse.urlencode({
        "q": query,
        "fields": fields,
        "pageSize": 100,
        "supportsAllDrives": "true",
        "includeItemsFromAllDrives": "true"
    })
    url = f"https://www.googleapis.com/drive/v3/files?{params}"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as response:
        return json.loads(response.read().decode("utf-8")).get("files", [])

def get_file_content(access_token, file_id):
    headers = {"Authorization": f"Bearer {access_token}"}
    url = f"https://www.googleapis.com/drive/v3/files/{file_id}?alt=media"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as response:
        return response.read()

def main():
    try:
        access_token = refresh_tokens()
        root_folder = "1_rV47JiauhIlZasrEeztXz5TUhWPCdXk"
        folders = drive_list_files(access_token, f"'{root_folder}' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false")
        
        print(f"Subfolders found: {len(folders)}")
        listos = []
        for f in folders:
            fid = f["id"]
            data_files = drive_list_files(access_token, f"'{fid}' in parents and name='data.json' and trashed=false")
            if data_files:
                content = get_file_content(access_token, data_files[0]["id"])
                pdata = json.loads(content.decode("utf-8"))
                estado = pdata.get("estado", "pendiente")
                titulo = pdata.get("titulo", pdata.get("nombre", "N/A"))
                if estado.strip().lower() == "listo":
                    listos.append((titulo, fid))
                print(f"Product: '{titulo}' | Estado: '{estado}'")
        
        print(f"\nSummary: {len(listos)} products are 'listo':")
        for title, fid in listos:
            print(f"- '{title}' (ID: {fid})")
            
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()
