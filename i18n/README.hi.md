# LaunchNext

**भाषाएँ**: [English](../README.md) | [中文](README.zh.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [हिन्दी](README.hi.md) | [Tiếng Việt](README.vi.md) | [Italiano](README.it.md) | [Čeština](README.cs.md)

## 📥 डाउनलोड

**[यहाँ डाउनलोड करें](https://github.com/RoversX/LaunchNext/releases/latest)** - नवीनतम संस्करण प्राप्त करें

🌐 **वेबसाइट**: [closex.org/launchnext](https://closex.org/launchnext/)  
📚 **दस्तावेज़**: [docs.closex.org/launchnext](https://docs.closex.org/launchnext/)

⭐ कृपया [LaunchNext](https://github.com/RoversX/LaunchNext) और विशेष रूप से मूल प्रोजेक्ट [LaunchNow](https://github.com/ggkevinnnn/LaunchNow) को स्टार दें!

| | |
|:---:|:---:|
| ![](../public/banner.webp) | ![](../public/setting1.webp) |
| ![](../public/setting2.webp) | ![](../public/setting3.webp) |

macOS Tahoe ने Launchpad हटा दिया है, और यह इतना उपयोग करना कठिन है, यह आपके Bio GPU का उपयोग नहीं करता। कृपया Apple, कम से कम लोगों को वापस स्विच करने का विकल्प तो दें। उससे पहले, यहाँ है LaunchNext।

*[LaunchNow](https://github.com/ggkevinnnn/LaunchNow) (ggkevinnnn) पर आधारित — मूल प्रोजेक्ट को बहुत-बहुत धन्यवाद!❤️*

*LaunchNow ने GPL 3 लाइसेंस चुना है। LaunchNext समान लाइसेंसिंग शर्तों का पालन करता है।*

⚠️ **यदि macOS एप्लिकेशन को ब्लॉक कर दे, तो टर्मिनल में यह चलाएं:**
```bash
sudo xattr -r -d com.apple.quarantine /Applications/LaunchNext.app
```
**क्यों**: मैं Apple का डेवलपर सर्टिफिकेट नहीं खरीद सकता ($99/वर्ष), इसलिए macOS unsigned एप्लिकेशन को ब्लॉक करता है। यह कमांड quarantine फ्लैग हटाकर इसे चलने देता है। **केवल विश्वसनीय एप्लिकेशन के लिए इस कमांड का उपयोग करें।**

## LaunchNext क्या देता है

- ✅ **पुराने सिस्टम Launchpad से वन-क्लिक आयात** - नेटिव Launchpad SQLite डेटाबेस को सीधे पढ़कर फ़ोल्डर, ऐप स्थितियाँ और लेआउट पुनर्स्थापित करता है
- ✅ **मैनुअल ऐप संगठन** - ऐप्स को व्यवस्थित करें, फ़ोल्डर बनाएं और अपनी पसंद का लेआउट रखें
- ✅ **दो रेंडरिंग पथ** - संगतता के लिए `Legacy Engine` और सर्वोत्तम अनुभव के लिए `Next Engine + Core Animation`
- ✅ **कॉम्पैक्ट और पूर्णस्क्रीन मोड** - अलग-अलग सेटिंग्स के साथ
- ✅ **कीबोर्ड-केंद्रित वर्कफ़्लो** - तेज़ खोज, नेविगेशन और लॉन्च
- ✅ **CLI / TUI समर्थन** - टर्मिनल से लेआउट देखें और प्रबंधित करें
- ✅ **Hot Corner और नेटिव जेस्चर सक्रियण** - LaunchNext खोलने के कई वैश्विक तरीके
- ✅ **ऐप्स को सीधे Dock में खींचें** - Core Animation इंजन में उपलब्ध
- ✅ **Markdown रिलीज़ नोट्स वाला अपडेट सेंटर** - अधिक समृद्ध इन-ऐप अपडेट अनुभव
- ✅ **बैकअप और पुनर्स्थापन टूल** - अधिक सुरक्षित एक्सपोर्ट और रिकवरी
- ✅ **एक्सेसिबिलिटी और कंट्रोलर समर्थन** - वॉयस फ़ीडबैक और कंट्रोलर नेविगेशन बेहतर
- ✅ **बहुभाषी समर्थन** - व्यापक लोकलाइज़ेशन कवरेज

## macOS Tahoe ने क्या छीन लिया

- ❌ कोई कस्टम ऐप संगठन नहीं
- ❌ कोई उपयोगकर्ता-निर्मित फ़ोल्डर नहीं
- ❌ कोई ड्रैग-एंड-ड्रॉप कस्टमाइज़ेशन नहीं
- ❌ कोई विजुअल ऐप प्रबंधन नहीं
- ❌ जबरदस्ती श्रेणीबद्ध समूहीकरण

## डेटा स्टोरेज

ऐप डेटा यहाँ संग्रहीत होता है:

```text
~/Library/Application Support/LaunchNext/Data.store
```

## नेटिव Launchpad इंटीग्रेशन

LaunchNext सिस्टम Launchpad डेटाबेस को सीधे पढ़ सकता है:

```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## स्थापना

### आवश्यकताएँ

- macOS 26 (Tahoe) या बाद का संस्करण
- Apple Silicon या Intel प्रोसेसर
- Xcode 26 (सोर्स से बिल्ड करने के लिए)

### सोर्स से बिल्ड करें

1. **रिपॉजिटरी क्लोन करें**
   ```bash
   git clone https://github.com/RoversX/LaunchNext.git
   cd LaunchNext
   ```

2. **Xcode में खोलें**
   ```bash
   open LaunchNext.xcodeproj
   ```

3. **बिल्ड और रन करें**
   - अपना टार्गेट डिवाइस चुनें
   - `⌘+R` दबाकर बिल्ड और रन करें
   - या `⌘+B` दबाकर केवल बिल्ड करें

### कमांड लाइन बिल्ड

**सामान्य बिल्ड:**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release
```

**यूनिवर्सल बाइनरी बिल्ड (Intel + Apple Silicon):**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

## उपयोग

### शुरुआत करना

1. LaunchNext पहली बार चलने पर सभी इंस्टॉल किए गए ऐप्स स्कैन करता है
2. अपना पुराना Launchpad लेआउट आयात करें या खाली लेआउट से शुरू करें
3. खोज, कीबोर्ड, ड्रैग-एंड-ड्रॉप और फ़ोल्डरों से ऐप्स व्यवस्थित करें
4. सेटिंग्स खोलकर इंजन, लेआउट मोड, सक्रियण विधियाँ और ऑटोमेशन कॉन्फ़िगर करें

### अपना Launchpad आयात करें

1. सेटिंग्स खोलें
2. **Import Launchpad** पर क्लिक करें
3. आपका मौजूदा लेआउट और फ़ोल्डर स्वचालित रूप से आयात हो जाएंगे

### इंजन और लेआउट मोड

- **Legacy Engine** - अधिकतम संगतता के लिए पुराने रेंडरिंग पथ को बनाए रखता है
- **Next Engine + Core Animation** - बेहतर अनुभव और नए फीचर्स के लिए अनुशंसित
- **कॉम्पैक्ट / पूर्णस्क्रीन** - LaunchNext दोनों मोड को सपोर्ट करता है और अलग-अलग सेटिंग्स रख सकता है

## मुख्य फीचर

### सक्रियण और इनपुट

- **Hot Corner समर्थन** - कॉन्फ़िगर करने योग्य स्क्रीन कोने से LaunchNext खोलें
- **प्रायोगिक नेटिव जेस्चर समर्थन** - चार-उंगली pinch / tap क्रियाएँ
- **ग्लोबल शॉर्टकट समर्थन** - कहीं से भी LaunchNext खोलें
- **Dock में ड्रैग** - Core Animation इंजन के साथ ऐप्स को सीधे macOS Dock में दें

### ऑटोमेशन और पावर यूज़र वर्कफ़्लो

- **CLI / TUI समर्थन** - लेआउट देखें, ऐप्स खोजें, फ़ोल्डर बनाएं, ऐप्स स्थानांतरित करें और वर्कफ़्लो ऑटोमेट करें
- **agent-अनुकूल वर्कफ़्लो** - टर्मिनल-आधारित AI agent और shell automation के साथ अच्छा काम करता है
- **सेटिंग्स से कमांड लाइन सक्षम करें** - प्रबंधित `launchnext` कमांड को इंस्टॉल या हटाएँ

### अपडेट अनुभव

- **इन-ऐप अपडेट सेंटर** - ऐप छोड़े बिना अपडेट जाँचें
- **Markdown रिलीज़ नोट्स** - सेटिंग्स में अधिक समृद्ध रिलीज़ नोट्स दृश्य
- **आधुनिक नोटिफिकेशन API** - नए macOS संस्करणों के लिए अपडेटेड नोटिफिकेशन डिलीवरी

### बैकअप और पुनर्स्थापन

- सेटिंग्स से बैकअप बनाएं और पुनर्स्थापित करें
- अधिक विश्वसनीय बैकअप एक्सपोर्ट व्यवहार
- अस्थायी फ़ाइलों और सफ़ाई का अधिक सुरक्षित प्रबंधन

### एक्सेसिबिलिटी और नेविगेशन

- **वॉइस फ़ीडबैक समर्थन** - नेविगेशन के दौरान ऐप्स और फ़ोल्डरों के नाम सुनाता है
- **कंट्रोलर समर्थन** - गेम कंट्रोलर के साथ LaunchNext और फ़ोल्डरों को चलाएँ
- **कीबोर्ड-केंद्रित इंटरैक्शन** - माउस के बिना तेज़ खोज और नेविगेशन

## प्रदर्शन और स्थिरता

- स्मूथ ब्राउज़िंग के लिए बुद्धिमान आइकन कैशिंग
- बड़ी लाइब्रेरी के लिए lazy loading और बैकग्राउंड स्कैनिंग
- सेटिंग्स और नेविगेशन के बीच बेहतर स्टेट सिंक्रोनाइज़ेशन
- अपडेट, बैकअप एक्सपोर्ट और जेस्चर रिकवरी की बेहतर विश्वसनीयता

## समस्या निवारण

### सामान्य समस्याएँ

**Q: ऐप शुरू नहीं हो रहा?**  
A: सुनिश्चित करें कि आप macOS 26 या बाद का संस्करण चला रहे हैं, ज़रूरत हो तो quarantine हटाएँ, और केवल विश्वसनीय build चलाएँ।

**Q: कौन सा इंजन उपयोग करना चाहिए?**  
A: `Next Engine + Core Animation` सर्वोत्तम अनुभव के लिए अनुशंसित है। `Legacy Engine` केवल तभी उपयोग करें जब आपको पुराने compatibility path की आवश्यकता हो।

**Q: CLI कमांड अभी तक क्यों नहीं है?**  
A: पहले सेटिंग्स में command line interface सक्षम करें। LaunchNext आपके लिए प्रबंधित `launchnext` shim इंस्टॉल और हटा सकता है।

## योगदान

योगदान का स्वागत है।

1. रिपॉजिटरी fork करें
2. फीचर ब्रांच बनाएं (`git checkout -b feature/amazing-feature`)
3. अपने बदलाव commit करें (`git commit -m 'Add amazing feature'`)
4. ब्रांच push करें (`git push origin feature/amazing-feature`)
5. Pull Request खोलें

### विकास दिशानिर्देश

- Swift शैली नियमों का पालन करें
- जटिल लॉजिक के लिए सार्थक टिप्पणियाँ जोड़ें
- जहाँ संभव हो, कई macOS संस्करणों पर परीक्षण करें
- प्रयोगात्मक फीचर को असंबंधित फ़ाइलों में न फैलाएँ
- हटाई जा सकने वाली integrations को यथासंभव अलग रखें

## ऐप प्रबंधन का भविष्य

जब Apple अनुकूलन योग्य app launcher से दूर जा रहा है, LaunchNext आधुनिक macOS पर मैनुअल संगठन, उपयोगकर्ता नियंत्रण और तेज़ पहुँच को बनाए रखने की कोशिश करता है।

**LaunchNext** केवल Launchpad का विकल्प नहीं है — यह workflow regression के लिए एक व्यावहारिक उत्तर है।

---

**LaunchNext** - अपने ऐप लॉन्चर पर नियंत्रण वापस पाएँ 🚀

*उन macOS उपयोगकर्ताओं के लिए जो customization पर समझौता नहीं करना चाहते।*

## विकास उपकरण

- Claude Code
- Cursor
- OpenAI Codex CLI
- Perplexity
- Google

- प्रयोगात्मक gesture समर्थन [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) और [KrishKrosh](https://github.com/KrishKrosh/OpenMultitouchSupport) के fork पर आधारित है।❤️

![GitHub downloads](https://img.shields.io/github/downloads/RoversX/LaunchNext/total)
