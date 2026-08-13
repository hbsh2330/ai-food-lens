# Food Nutrition Flutter app

This UI sends a selected image to the FastAPI `POST /predict` endpoint and displays the returned nutrition data.

## Run after Flutter is installed

```powershell
cd food_nutrition_app
flutter create --platforms=android .
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

For a physical Android device, replace `10.0.2.2` with the Windows PC's local IP address and ensure the FastAPI server is running with `--host 0.0.0.0`.
