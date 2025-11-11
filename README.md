# Stable Diffusion Mobile Interface

<p align="center">
  <b>Professional mobile UI for Stable Diffusion image generation and inpainting</b><br>
  Control your local Stable Diffusion instance from your phone
</p>

---

## 📱 About
A Flutter mobile interface that allows remote access to a locally-hosted Stable Diffusion instance. Designed for workflow optimization, this app turns your phone into a full-featured AI image generation and editing tool.

---

## 📸 Screenshots

<p align="center">
  <img src="https://github.com/KareemNashef/SD-UI/blob/main/screens/Screenshot_2025-11-01-01-30-35-938_com.example.sd_companion-edit.png?raw=true" width="45%"/>
  <img src="https://github.com/KareemNashef/SD-UI/blob/main/screens/Screenshot_2025-11-01-01-30-04-570_com.example.sd_companion-edit.png?raw=true" width="45%"/><br><br>
  <img src="https://github.com/KareemNashef/SD-UI/blob/main/screens/Screenshot_2025-11-01-01-31-16-872_com.example.sd_companion-edit.png?raw=true" width="45%"/>
  <img src="https://github.com/KareemNashef/SD-UI/blob/main/screens/Screenshot_2025-11-01-01-26-08-559_com.example.sd_companion-edit.png?raw=true" width="45%"/>
</p>

---

## ✨ Features

### Image Generation
- **Inpainting**: Edit specific regions of images  
- **Batch Generation**: Queue multiple generation jobs  

### Professional Workflow Tools
- **Model Profile Management**: Save and switch between checkpoint configurations  
- Custom parameter presets per model  
- CFG Scale, steps, samplers per profile  
- Quick model switching  
- **Real-Time Progress Tracking**: Live generation status with previews  
- **Parameter Controls**: Full access to prompts, steps, samplers, CFG, denoising  

### Mobile-Optimized UX
- Intuitive touch interface  
- Responsive design for all screen sizes  
- Browse and manage generated images  

### Advanced Inpainting
- Mask editor with brush size control  
- Mask preview to compare with original image  

---

## 🛠️ Technical Stack
- **Frontend**: Flutter (Dart)  
- **Backend Communication**: REST API  
- **Image Processing**: Flutter image manipulation  
- **State Management**: Provider  
- **Networking**: HTTP/HTTPS with dio  
- **Local Storage**: Shared Preferences  

---

## 🏗️ Architecture

```

Mobile App (Flutter)
↓ HTTP REST API
Local Computer (Stable Diffusion WebUI)
↓
GPU Processing
↓
Generated Images → Mobile Device

````

---

## 🚀 Key Features
- Efficient image transfer via Base64 encoding  
- Progressive loading with preview updates  
- Recent generation caching  
- Connection health checks, retry logic, and timeout handling  
- Real-time step progress, estimated time, and preview images  

---

## 📋 Requirements

### Server
- Stable Diffusion WebUI installed locally  
- API enabled (`--api` flag)  
- Network accessible (`--listen` flag)  

### Mobile
- Same local network as SD server (or VPN/port forwarding)  

---

## 🔧 Setup

1. **Launch Stable Diffusion Server**
```bash
python launch.py --api --listen
````

2. **Build Mobile App**

```bash
git clone https://github.com/KareemNashef/sd-mobile-ui.git
cd sd-mobile-ui
flutter pub get
flutter run
```

3. **Connect**

* Enter local IP and port in the app
* Test connection
* Start generating

---

## 🎯 Use Cases

* Mobile workflow for AI art generation
* Comfortable art creation on bed or couch
* Remote access via VPN
* Tablet optimization for inpainting
* Quick prompt and parameter iteration

---

## 🔐 Security Notes

* Local network only by default
* No external API calls or data collection
* Processing happens on your hardware
* VPN recommended for remote access

---

## 🎓 Learning Outcomes

* REST API integration and error handling
* Asynchronous Dart programming
* Mobile image processing
* Network optimization
* Complex UX design for mobile AI tools
* Progressive enhancement and iterative development

---

## 📧 Contact

**Kareem Nashef**
📩 [Kareem.na@outlook.com](mailto:Kareem.na@outlook.com)
🔗 [LinkedIn](https://linkedin.com/in/kareem-nashef)
💻 [GitHub](https://github.com/KareemNashef)

---

<p align="center">
Built with Flutter 💙  
</p>

<p align="center">
Making AI art generation accessible on mobile
</p>
