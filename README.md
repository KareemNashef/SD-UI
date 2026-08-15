# Stable Diffusion Mobile Interface

<p align="center">
  <b>Professional mobile UI for Stable Diffusion image generation and inpainting</b><br>
  Control your local Forge Neo or ComfyUI instance from your phone
</p>

---

## 📱 About
A Flutter mobile interface that allows remote access to a locally-hosted Stable Diffusion instance. Designed for workflow optimization, this app turns your phone into a full-featured AI image generation and editing tool.

The app supports exactly one active backend at a time - **Forge Neo** (A1111-compatible) or **ComfyUI** - selected from Settings. The active backend is always shown with its own color, icon, and label throughout the connection, settings, and progress screens, so it's never ambiguous which server you're talking to.

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

### Forge Neo server
- Forge Neo (A1111-compatible WebUI) installed locally
- API enabled (`--api` flag)
- Network accessible (`--listen` flag)

### ComfyUI server
- A local/self-hosted ComfyUI instance (no authentication - Comfy Cloud and
  auth are out of scope)
- Reachable on your network at its default port (8188) or a custom one

### Mobile
- Same local network as the server (or VPN/port forwarding)

---

## 🔧 Setup

1. **Launch your server**

Forge Neo:
```bash
python launch.py --api --listen
```

ComfyUI:
```bash
python main.py --listen
```

2. **Build Mobile App**

```bash
git clone https://github.com/KareemNashef/sd-mobile-ui.git
cd sd-mobile-ui
flutter pub get
flutter run
```

3. **Connect**

* On first launch, pick Forge Neo or ComfyUI in the connection screen
* Enter the server's local IP and port
* Test connection

4a. **Forge Neo**: select a checkpoint, set your sampler/steps/CFG in
Settings, and start generating from the Inpaint tab as usual.

4b. **ComfyUI**: in Settings → Workflows, import the editor-format workflow
JSON you exported from the ComfyUI web UI (the same file, no separate
"API format" export needed, no favoriting required in ComfyUI first). On
import, tell the app whether the workflow is **Text to Image**, **Image to
Image**, or **Inpainting** - this decides what the Inpaint tab shows (no
canvas at all for text-to-image, a plain image picker for image-to-image,
full mask painting for inpainting).

The app then analyzes the workflow's graph itself: it walks back from the
sampler node to find the diffusion model, CLIP, and VAE loaders, the
sampler's own seed/steps/cfg/sampler/scheduler/denoise widgets, and (when
present) the empty-latent width/height/batch-size - all shown under
"Workflow Settings". The prompt, negative prompt, and input image are
detected the same way and bound straight into the existing prompt/negative-
prompt/image canvas, so nothing needs to be marked or favorited by hand.

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
