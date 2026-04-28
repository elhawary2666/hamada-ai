# 🤖 حماده AI

مساعد شخصي ذكي — كل بياناتك على جهازك بس 🔒

[![Build](https://github.com/YOUR_USERNAME/hamada-ai/actions/workflows/build.yml/badge.svg)](https://github.com/YOUR_USERNAME/hamada-ai/actions/workflows/build.yml)
![Flutter](https://img.shields.io/badge/Flutter-3.27.4-blue)
![Dart](https://img.shields.io/badge/Dart-3.4+-blue)
![Android](https://img.shields.io/badge/Android-API_26+-green)

---

## ✨ المميزات

| الميزة | الوصف |
|--------|-------|
| 💬 **Chat بالعامية** | محادثة طبيعية بالعربي المصري مع Groq API |
| 💰 **إدارة مالية** | تتبع المصروفات، الميزانية، تقسيم الحساب، تنبؤات |
| ✅ **مهام ومواعيد** | تنظيم يومي مع أولويات وتذكيرات |
| 📝 **ملاحظات** | تدوين سريع مع تثبيت وبحث |
| 🎯 **عادات** | تتبع العادات اليومية مع streak |
| 👥 **علاقات** | ملاحظات عن الناس المهمين في حياتك |
| 🧠 **ذاكرة ذكية** | يتذكر تفضيلاتك ومعلوماتك عبر المحادثات |
| 📊 **تقارير** | تقرير أسبوعي مالي + تنبؤ الشهر الجاي |
| ⚠️ **وضع الطوارئ** | يتصرف بحذر أكتر لما الرصيد ينخفض |

---

## 🚀 تشغيل المشروع

### المتطلبات
- Flutter 3.27.4
- Android SDK (API 26+)
- Groq API Key (مجاني من [console.groq.com](https://console.groq.com))

### الخطوات

```bash
# 1. Clone
git clone https://github.com/YOUR_USERNAME/hamada-ai.git
cd hamada-ai

# 2. Install dependencies
flutter pub get

# 3. Generate Riverpod providers
dart run build_runner build --delete-conflicting-outputs

# 4. Run
flutter run
```

### API Key
بعد ما تشغل التطبيق — روح **الإعدادات** وحط الـ Groq API Key.

---

## 🏗️ Architecture

```
lib/
├── core/
│   ├── constants/      # Prompts, colors
│   ├── database/       # SQLite (v5) — local only
│   ├── di/             # Riverpod providers
│   ├── router/         # go_router
│   ├── services/       # AI service, Memory service
│   ├── shell/          # Bottom navigation
│   └── theme/          # App colors
└── features/
    ├── chat/           # Main AI chat
    ├── finance/        # Transactions, budgets, goals
    ├── habits/         # Daily habits + streak
    ├── notes/          # Quick notes
    ├── onboarding/     # First launch
    ├── planner/        # Tasks + appointments
    ├── relationships/  # People + notes
    └── settings/       # API key, reports, data
```

**Stack:** Flutter + Riverpod 2.5 + SQLite (sqflite) + Groq API (llama-3.3-70b)

---

## 🔒 الخصوصية

كل البيانات محفوظة **محلياً على جهازك فقط** — مش بتتبعت أي سيرفر.  
الـ AI بيتواصل مع Groq API بس للرد على رسائلك.

---

## 📦 CI/CD

الـ GitHub Actions workflow بيعمل:
1. **Analyze** — flutter analyze على كل push
2. **Test** — unit tests تلقائية
3. **Build Debug APK** — على كل push
4. **Build Release APK** — على main/master فقط

الـ APK بيتحمل من **Actions → Artifacts**.

---

## 🛠️ Development Notes

- الـ `*.g.dart` files مش في الـ repo — بتتولد تلقائياً بـ `build_runner`
- لو عملت تعديل على أي `@riverpod` provider: `dart run build_runner build --delete-conflicting-outputs`
- DB version حالياً: **v5**
