import os
import json

token_path = os.path.expandvars(r"%APPDATA%\com.example\novaled_app\auth_tokens.json")
if not os.path.exists(token_path):
    token_path = r"C:\Users\UnseR\AppData\Roaming\com.example\novaled_app\auth_tokens.json"

print(f"Checking token path: {token_path}")
if os.path.exists(token_path):
    print("Tokens file exists!")
    with open(token_path, 'r') as f:
        data = json.load(f)
        print("Keys in token file:", list(data.keys()))
        print("Token expiry:", data.get("expiry"))
        print("Has refreshToken:", "refreshToken" in data and bool(data["refreshToken"]))
else:
    print("Tokens file NOT found.")
