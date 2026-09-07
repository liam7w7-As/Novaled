import json
import urllib.request
import urllib.parse
from datetime import datetime

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

def drive_list_files(access_token, query, fields="files(id, name, modifiedTime, parents)"):
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

def main():
    try:
        access_token = refresh_tokens()
        # Search for data.json files in Google Drive
        files = drive_list_files(access_token, "name='data.json' and trashed=false", fields="files(id, name, modifiedTime, parents)")
        
        # Sort by modification time descending
        files.sort(key=lambda x: x.get("modifiedTime", ""), reverse=True)
        
        print("Recent data.json updates on Google Drive:")
        for idx, f in enumerate(files[:15]):
            fid = f["id"]
            mtime = f["modifiedTime"]
            parents = f.get("parents", [])
            parent_name = "N/A"
            if parents:
                # Get parent folder info
                headers = {"Authorization": f"Bearer {access_token}"}
                url = f"https://www.googleapis.com/drive/v3/files/{parents[0]}?supportsAllDrives=true"
                req = urllib.request.Request(url, headers=headers)
                try:
                    with urllib.request.urlopen(req) as resp:
                        parent_info = json.loads(resp.read().decode("utf-8"))
                        parent_name = parent_info.get("name", "N/A")
                except:
                    pass
            print(f"{idx+1}. Product Folder: '{parent_name}' | data.json Modified: {mtime} | ID: {fid}")
            
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()
