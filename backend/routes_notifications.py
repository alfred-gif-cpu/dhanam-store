from datetime import datetime
from fastapi import APIRouter, HTTPException, Body
from pydantic import BaseModel
from database import db

router = APIRouter(prefix="/notifications", tags=["Notifications"])

fcm_tokens_collection = db["fcm_tokens"]
notifications_collection = db["notifications"]


class RegisterTokenRequest(BaseModel):
    token: str
    user_id: str = ""


class SendNotificationRequest(BaseModel):
    title: str
    body: str
    user_id: str = ""
    topic: str = ""
    data: dict = {}


@router.post("/register")
async def register_token(req: RegisterTokenRequest):
    await fcm_tokens_collection.update_one(
        {"token": req.token},
        {"$set": {
            "token": req.token,
            "user_id": req.user_id,
            "updated_at": datetime.utcnow().isoformat(),
        }},
        upsert=True,
    )
    return {"status": "registered"}


@router.post("/send")
async def send_notification(req: SendNotificationRequest):
    try:
        import firebase_admin
        from firebase_admin import messaging
    except ImportError:
        raise HTTPException(status_code=500, detail="firebase-admin not installed")

    if not firebase_admin._apps:
        firebase_admin.initialize_app()

    notification = messaging.Notification(title=req.title, body=req.body)

    sent_count = 0

    if req.topic:
        message = messaging.Message(
            notification=notification,
            topic=req.topic,
            data={k: str(v) for k, v in req.data.items()},
        )
        messaging.send(message)
        sent_count = 1
    elif req.user_id:
        tokens = await fcm_tokens_collection.find({"user_id": req.user_id}).to_list(100)
        for t in tokens:
            try:
                message = messaging.Message(
                    notification=notification,
                    token=t["token"],
                    data={k: str(v) for k, v in req.data.items()},
                )
                messaging.send(message)
                sent_count += 1
            except Exception:
                await fcm_tokens_collection.delete_one({"_id": t["_id"]})
    else:
        tokens = await fcm_tokens_collection.find().to_list(1000)
        for t in tokens:
            try:
                message = messaging.Message(
                    notification=notification,
                    token=t["token"],
                    data={k: str(v) for k, v in req.data.items()},
                )
                messaging.send(message)
                sent_count += 1
            except Exception:
                await fcm_tokens_collection.delete_one({"_id": t["_id"]})

    await notifications_collection.insert_one({
        "title": req.title,
        "body": req.body,
        "user_id": req.user_id,
        "topic": req.topic,
        "data": req.data,
        "sent_count": sent_count,
        "created_at": datetime.utcnow().isoformat(),
    })

    return {"status": "sent", "sent_count": sent_count}


@router.get("/history/{user_id}")
async def get_notifications(user_id: str):
    notifs = await notifications_collection.find(
        {"$or": [{"user_id": user_id}, {"user_id": ""}, {"topic": {"$ne": ""}}]}
    ).sort("created_at", -1).to_list(50)

    for n in notifs:
        n["id"] = str(n.pop("_id"))

    return {"notifications": notifs}
