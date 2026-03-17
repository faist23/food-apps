# Camera Feature Setup

## Required: Add Camera Permission

The nutrition label scanner requires camera access. You need to add the camera usage description to your app:

### Steps:

1. **In Xcode**, select your BiteLedger target
2. Go to the **Info** tab
3. Add a new entry under "Custom iOS Target Properties":
   - **Key**: `Privacy - Camera Usage Description` (or `NSCameraUsageDescription`)
   - **Value**: `BiteLedger needs camera access to scan nutrition labels and autofill nutrition facts.`

### Alternative: Add to Info.plist directly

If your project has an Info.plist file, add this entry:

```xml
<key>NSCameraUsageDescription</key>
<string>BiteLedger needs camera access to scan nutrition labels and autofill nutrition facts.</string>
```

## How It Works

1. **NutritionLabelScannerView** - Full-screen camera interface with live preview
2. **Vision Framework** - Apple's OCR to extract text from nutrition labels
3. **NutritionLabelParser** - Smart parsing to identify and extract nutrition values
4. **Auto-fill** - Extracted data automatically populates the manual entry form

## Features

- ✅ Live camera preview
- ✅ Flash toggle for better lighting
- ✅ Visual guidance frame
- ✅ Real-time text recognition
- ✅ Automatic field population
- ✅ FDA nutrition label format support
- ✅ Error handling with helpful messages

## Usage

From the Manual Food Entry screen:
1. Tap "Autofill with your Camera"
2. Position the nutrition label in the frame
3. Tap "Capture Photo"
4. Review extracted data
5. Tap "Use This Data" to fill the form

The scanner automatically detects:
- Serving Size
- Calories
- Total Fat, Saturated Fat, Trans Fat
- Cholesterol
- Sodium
- Total Carbohydrates, Fiber, Sugars
- Protein
- Vitamin D, Calcium, Iron, Potassium
