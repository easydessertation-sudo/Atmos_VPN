import os
import sys
import time
import subprocess
import requests
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

# Reconfigure stdout for UTF-8 compatibility on Windows
sys.stdout.reconfigure(encoding='utf-8')

# Constants
PORT = 5005
BASE_URL = f"http://127.0.0.1:{PORT}"
TEST_EMAIL = "test_fcm_user@atmosvpn.com"
TEST_PASSWORD = "Password123!"
TEST_NAME = "FCM Test User"

def run_tests():
    # 1. Load dotenv and setup direct DB session to verify and clean up
    from dotenv import load_dotenv
    load_dotenv()
    
    db_url = os.environ.get("DATABASE_URL")
    if not db_url:
        print("❌ DATABASE_URL is not set in .env")
        sys.exit(1)
        
    engine = create_engine(db_url)
    SessionLocal = sessionmaker(bind=engine)
    db = SessionLocal()

    # Pre-test cleanup: delete existing user if any
    print("🧹 Cleaning up old test data...")
    db.execute(text("DELETE FROM users WHERE email = :email"), {"email": TEST_EMAIL})
    db.execute(text("DELETE FROM pending_signups WHERE email = :email"), {"email": TEST_EMAIL})
    db.commit()

    # 2. Start Uvicorn backend server
    print(f"🚀 Starting Uvicorn backend on port {PORT}...")
    server_process = subprocess.Popen(
        [
            sys.executable,
            "-m",
            "uvicorn",
            "app:app",
            "--port",
            str(PORT),
            "--host",
            "127.0.0.1"
        ]
    )

    # Wait for the server to boot up
    time.sleep(3)
    healthy = False
    for i in range(10):
        try:
            r = requests.get(f"{BASE_URL}/", timeout=2)
            if r.status_code == 200:
                healthy = True
                print("✅ Server is healthy and responding!")
                break
        except Exception:
            pass
        print(f"⏳ Waiting for server... ({i+1}/10)")
        time.sleep(1)

    if not healthy:
        print("❌ Server failed to start or respond!")
        server_process.terminate()
        sys.exit(1)

    try:
        # 3. Register user
        print("\n=== STEP 1: Registering Test User ===")
        reg_payload = {
            "email": TEST_EMAIL,
            "password": TEST_PASSWORD,
            "full_name": TEST_NAME
        }
        r = requests.post(f"{BASE_URL}/api/auth/register", json=reg_payload)
        print(f"Register status: {r.status_code}, response: {r.json()}")
        assert r.status_code == 201, "Failed to register test user"

        # 4. Fetch verification code directly from database
        print("\n=== STEP 2: Fetching verification code from database ===")
        pending = db.execute(
            text("SELECT code FROM pending_signups WHERE email = :email"),
            {"email": TEST_EMAIL}
        ).fetchone()
        
        if not pending:
            raise RuntimeError("Pending signup record not found in database")
        
        verification_code = pending[0]
        print(f"Fetched verification code: {verification_code}")

        # 5. Verify email to complete signup and get token
        print("\n=== STEP 3: Verifying email ===")
        verify_payload = {
            "email": TEST_EMAIL,
            "code": verification_code
        }
        r = requests.post(f"{BASE_URL}/api/auth/verify-email", json=verify_payload)
        print(f"Verify status: {r.status_code}")
        assert r.status_code == 200, "Verification failed"
        
        verify_data = r.json()
        assert "access_token" in verify_data["data"], "No access token in verification response"
        access_token = verify_data["data"]["access_token"]
        print("✅ Received access token successfully!")

        headers = {"Authorization": f"Bearer {access_token}"}

        # 6. Register FCM token
        print("\n=== STEP 4: Registering FCM Token ===")
        fcm_payload = {
            "fcm_token": "dummy_fcm_token_12345",
            "device_id": "test_device_id_abcde",
            "platform": "android"
        }
        r = requests.post(f"{BASE_URL}/api/users/fcm-token", json=fcm_payload, headers=headers)
        print(f"FCM register response: {r.json()}")
        assert r.status_code == 200, "FCM registration failed"
        
        # Verify in DB
        user_db = db.execute(
            text("SELECT id FROM users WHERE email = :email"),
            {"email": TEST_EMAIL}
        ).fetchone()
        user_id = user_db[0]
        
        token_db = db.execute(
            text("SELECT fcm_token, device_id, platform FROM fcm_tokens WHERE user_id = :user_id"),
            {"user_id": user_id}
        ).fetchone()
        assert token_db is not None, "Token not found in database"
        assert token_db[0] == "dummy_fcm_token_12345", "Token value mismatch"
        assert token_db[1] == "test_device_id_abcde", "Device ID mismatch"
        assert token_db[2] == "android", "Platform mismatch"
        print("✅ FCM token successfully verified in the database!")

        # 7. Get Notifications with Pagination
        print("\n=== STEP 5: Getting Notifications with Pagination ===")
        r = requests.get(f"{BASE_URL}/api/notifications?limit=2&page=1", headers=headers)
        print(f"GET Notifications response status: {r.status_code}")
        notif_data = r.json()
        print(f"GET Notifications keys: {notif_data.keys()}")
        if "data" in notif_data:
            data = notif_data["data"]
            print(f"Data keys: {data.keys()}")
            assert "notifications" in data, "No notifications key in paginated data"
            assert "total" in data, "No total key in paginated data"
            assert "page" in data, "No page key in paginated data"
            assert "limit" in data, "No limit key in paginated data"
            print(f"Pagination metadata - page: {data['page']}, limit: {data['limit']}, total: {data['total']}, notifications count: {len(data['notifications'])}")
        else:
            raise AssertionError("Response JSON does not contain 'data' field")
        print("✅ Paginated notification endpoint is working flawlessly!")

        # 8. Trigger Test Notification to verify FCM flow logs simulation
        print("\n=== STEP 6: Triggering Test Notification ===")
        r = requests.post(f"{BASE_URL}/api/test/notifications/trigger", headers=headers)
        print(f"Trigger Notification response status: {r.status_code}, body: {r.json()}")
        assert r.status_code == 200, "Failed to trigger test notification"
        print("✅ Test notification trigger completed successfully!")

        # 9. Delete FCM token
        print("\n=== STEP 7: Deleting FCM Token ===")
        r = requests.delete(f"{BASE_URL}/api/users/fcm-token?device_id=test_device_id_abcde", headers=headers)
        print(f"FCM delete response status: {r.status_code}, body: {r.json()}")
        assert r.status_code == 200, "FCM deletion failed"
        
        # Verify deletion in DB
        token_db = db.execute(
            text("SELECT COUNT(*) FROM fcm_tokens WHERE user_id = :user_id"),
            {"user_id": user_id}
        ).scalar()
        assert token_db == 0, "FCM token still exists in database after delete"
        print("✅ FCM token successfully deleted and verified in the database!")

        print("\n🎉 ALL TESTS COMPLETED SUCCESSFULLY! 🎉")

    except AssertionError as e:
        print(f"\n❌ Assertion failed: {e}")
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
    finally:
        # Clean up database
        print("\n🧹 Cleaning up test user and records...")
        db.execute(text("DELETE FROM users WHERE email = :email"), {"email": TEST_EMAIL})
        db.execute(text("DELETE FROM pending_signups WHERE email = :email"), {"email": TEST_EMAIL})
        db.commit()
        db.close()

        # Stop server
        print("🛑 Stopping Uvicorn backend...")
        server_process.terminate()
        try:
            server_process.wait(timeout=5)
            print("🛑 Server terminated.")
        except subprocess.TimeoutExpired:
            server_process.kill()
            print("🛑 Server killed.")

if __name__ == "__main__":
    run_tests()
