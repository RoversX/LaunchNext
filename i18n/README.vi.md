# LaunchNext

**Ngôn ngữ**: [English](../README.md) | [中文](README.zh.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [हिन्दी](README.hi.md) | [Tiếng Việt](README.vi.md) | [Italiano](README.it.md) | [Čeština](README.cs.md)

## 📥 Tải xuống

**[Tải tại đây](https://github.com/RoversX/LaunchNext/releases/latest)** - Lấy phiên bản mới nhất

🌐 **Website**: [closex.org/launchnext](https://closex.org/launchnext/)  
📚 **Tài liệu**: [docs.closex.org/launchnext](https://docs.closex.org/launchnext/)

⭐ Hãy xem xét gắn sao cho [LaunchNext](https://github.com/RoversX/LaunchNext) và đặc biệt là dự án gốc [LaunchNow](https://github.com/ggkevinnnn/LaunchNow)!

| | |
|:---:|:---:|
| ![](../public/banner.webp) | ![](../public/setting1.webp) |
| ![](../public/setting2.webp) | ![](../public/setting3.webp) |

macOS Tahoe đã loại bỏ launchpad, và rất khó sử dụng, nó không sử dụng GPU Bio của bạn. Xin lỗi Apple, ít nhất hãy cho mọi người một tùy chọn để chuyển đổi trở lại. Trước đó, đây là LaunchNext.

*Được xây dựng dựa trên [LaunchNow](https://github.com/ggkevinnnn/LaunchNow) bởi ggkevinnnn — xin gửi lời cảm ơn rất lớn đến dự án gốc!❤️*

*LaunchNow đã chọn giấy phép GPL 3. LaunchNext tuân theo các điều khoản cấp phép tương tự.*

⚠️ **Nếu macOS chặn ứng dụng, hãy chạy lệnh này trong Terminal:**
```bash
sudo xattr -r -d com.apple.quarantine /Applications/LaunchNext.app
```
**Tại sao**: Tôi không đủ tiền mua chứng chỉ nhà phát triển của Apple ($99/năm), vì vậy macOS chặn các ứng dụng không được ký. Lệnh này loại bỏ cờ cách ly để cho phép ứng dụng chạy. **Chỉ sử dụng lệnh này cho các ứng dụng đáng tin cậy.**

## LaunchNext mang lại điều gì

- ✅ **Nhập một cú nhấp từ Launchpad hệ thống cũ** - đọc trực tiếp cơ sở dữ liệu SQLite Launchpad gốc để khôi phục thư mục, vị trí ứng dụng và bố cục
- ✅ **Tổ chức ứng dụng thủ công** - di chuyển ứng dụng, tạo thư mục và giữ bố cục theo ý bạn
- ✅ **Hai đường dẫn render** - `Legacy Engine` cho tương thích và `Next Engine + Core Animation` cho trải nghiệm tốt nhất
- ✅ **Chế độ gọn và toàn màn hình** - với hỗ trợ lưu cài đặt riêng
- ✅ **Workflow ưu tiên bàn phím** - tìm kiếm, điều hướng và mở ứng dụng nhanh
- ✅ **Hỗ trợ CLI / TUI** - kiểm tra và quản lý bố cục từ terminal
- ✅ **Kích hoạt bằng Hot Corner và cử chỉ gốc** - nhiều cách mở LaunchNext toàn cục
- ✅ **Kéo ứng dụng trực tiếp vào Dock** - có sẵn với engine Core Animation
- ✅ **Trung tâm cập nhật với release notes Markdown** - trải nghiệm cập nhật trong ứng dụng phong phú hơn
- ✅ **Công cụ sao lưu và khôi phục** - xuất và phục hồi an toàn hơn
- ✅ **Hỗ trợ trợ năng và tay cầm** - cải thiện phản hồi giọng nói và điều hướng bằng controller
- ✅ **Hỗ trợ đa ngôn ngữ** - phạm vi bản địa hóa rộng hơn

## Những gì macOS Tahoe đã lấy mất

- ❌ Không có tổ chức ứng dụng tùy chỉnh
- ❌ Không có thư mục do người dùng tạo
- ❌ Không có tùy chỉnh kéo và thả
- ❌ Không có quản lý ứng dụng trực quan
- ❌ Nhóm phân loại bắt buộc

## Lưu trữ dữ liệu

Dữ liệu ứng dụng được lưu tại:

```text
~/Library/Application Support/LaunchNext/Data.store
```

## Tích hợp Launchpad gốc

LaunchNext có thể đọc trực tiếp cơ sở dữ liệu Launchpad của hệ thống:

```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## Cài đặt

### Yêu cầu

- macOS 26 (Tahoe) trở lên
- Bộ xử lý Apple Silicon hoặc Intel
- Xcode 26 (để build từ mã nguồn)

### Xây dựng từ mã nguồn

1. **Clone kho lưu trữ**
   ```bash
   git clone https://github.com/RoversX/LaunchNext.git
   cd LaunchNext
   ```

2. **Mở bằng Xcode**
   ```bash
   open LaunchNext.xcodeproj
   ```

3. **Build và chạy**
   - Chọn thiết bị đích
   - Nhấn `⌘+R` để build và chạy
   - Hoặc `⌘+B` để chỉ build

### Build dòng lệnh

**Build thông thường:**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release
```

**Build universal binary (Intel + Apple Silicon):**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

## Sử dụng

### Bắt đầu

1. LaunchNext quét các ứng dụng đã cài đặt ở lần khởi chạy đầu tiên
2. Nhập bố cục Launchpad cũ hoặc bắt đầu từ bố cục trống
3. Dùng tìm kiếm, bàn phím, kéo thả và thư mục để sắp xếp ứng dụng
4. Mở Cài đặt để cấu hình engine, chế độ bố cục, cách kích hoạt và tự động hóa

### Nhập Launchpad của bạn

1. Mở Cài đặt
2. Nhấn **Import Launchpad**
3. Bố cục và thư mục hiện có của bạn sẽ được nhập tự động

### Engine và chế độ bố cục

- **Legacy Engine** - giữ đường dẫn render cũ để ưu tiên khả năng tương thích
- **Next Engine + Core Animation** - được khuyến nghị cho trải nghiệm tốt nhất và các tính năng mới hơn
- **Gọn / Toàn màn hình** - LaunchNext hỗ trợ cả hai chế độ và có thể lưu cài đặt riêng cho từng chế độ

## Tính năng chính

### Kích hoạt và đầu vào

- **Hỗ trợ Hot Corner** - mở LaunchNext từ một góc màn hình có thể cấu hình
- **Hỗ trợ cử chỉ gốc thử nghiệm** - hành động pinch / tap bằng bốn ngón tay
- **Hỗ trợ phím tắt toàn cục** - mở LaunchNext từ bất cứ đâu
- **Kéo vào Dock** - chuyển ứng dụng trực tiếp vào Dock của macOS bằng engine Core Animation

### Tự động hóa và workflow nâng cao

- **Hỗ trợ CLI / TUI** - xem bố cục, tìm ứng dụng, tạo thư mục, di chuyển ứng dụng và tự động hóa workflow
- **Workflow thân thiện với agent** - hoạt động tốt với AI agent dựa trên terminal và shell automation
- **Bật dòng lệnh từ Cài đặt** - cài đặt hoặc gỡ lệnh được quản lý `launchnext`

### Trải nghiệm cập nhật

- **Trung tâm cập nhật trong ứng dụng** - kiểm tra cập nhật mà không rời ứng dụng
- **Release notes Markdown** - hiển thị phong phú hơn ngay trong Cài đặt
- **API thông báo hiện đại** - đường dẫn thông báo được cập nhật cho các phiên bản macOS mới hơn

### Sao lưu và khôi phục

- Tạo và khôi phục bản sao lưu từ Cài đặt
- Hành vi xuất backup đáng tin cậy hơn
- Xử lý an toàn hơn với tệp tạm và quy trình dọn dẹp

### Trợ năng và điều hướng

- **Hỗ trợ phản hồi giọng nói** - đọc tên ứng dụng và thư mục khi điều hướng
- **Hỗ trợ tay cầm** - điều khiển LaunchNext và thư mục bằng game controller
- **Tương tác ưu tiên bàn phím** - tìm kiếm và điều hướng nhanh mà không cần chuột

## Hiệu năng và độ ổn định

- Bộ nhớ đệm biểu tượng thông minh cho trải nghiệm duyệt mượt hơn
- Tải lười và quét nền cho thư viện lớn
- Đồng bộ trạng thái tốt hơn giữa Cài đặt và điều hướng
- Độ tin cậy tốt hơn cho cập nhật, xuất sao lưu và khôi phục cử chỉ

## Khắc phục sự cố

### Vấn đề thường gặp

**Q: Ứng dụng không khởi động?**  
A: Hãy xác nhận bạn đang dùng macOS 26 trở lên, gỡ quarantine nếu cần, và đảm bảo bạn đang chạy một bản build đáng tin cậy.

**Q: Tôi nên dùng engine nào?**  
A: `Next Engine + Core Animation` được khuyến nghị cho trải nghiệm tốt nhất. Chỉ dùng `Legacy Engine` nếu bạn thực sự cần đường dẫn tương thích cũ.

**Q: Tại sao lệnh CLI vẫn chưa có?**  
A: Hãy bật giao diện dòng lệnh trong Cài đặt trước. LaunchNext có thể cài đặt và gỡ shim `launchnext` được quản lý cho bạn.

## Đóng góp

Mọi đóng góp đều được chào đón.

1. Fork kho lưu trữ
2. Tạo nhánh tính năng (`git checkout -b feature/amazing-feature`)
3. Commit thay đổi (`git commit -m 'Add amazing feature'`)
4. Push nhánh (`git push origin feature/amazing-feature`)
5. Mở Pull Request

### Hướng dẫn phát triển

- Tuân theo quy ước style của Swift
- Thêm comment có ý nghĩa cho logic phức tạp
- Kiểm tra trên nhiều phiên bản macOS khi có thể
- Tránh rải các tính năng thử nghiệm vào những file không liên quan
- Giữ các tích hợp có thể tháo rời được tách biệt nếu có thể

## Tương lai của quản lý ứng dụng

Khi Apple ngày càng rời xa các launcher có thể tùy biến, LaunchNext cố gắng giữ lại khả năng tổ chức thủ công, quyền kiểm soát của người dùng và truy cập nhanh trên macOS hiện đại.

**LaunchNext** không chỉ là bản thay thế Launchpad — nó là một phản hồi thực tế trước sự thụt lùi của workflow.

---

**LaunchNext** - Giành lại quyền kiểm soát launcher ứng dụng của bạn 🚀

*Dành cho người dùng macOS không muốn thỏa hiệp về khả năng tùy biến.*

## Công cụ phát triển

- Claude Code
- Cursor
- OpenAI Codex CLI
- Perplexity
- Google

- Hỗ trợ cử chỉ thử nghiệm được xây dựng trên [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) và fork của [KrishKrosh](https://github.com/KrishKrosh/OpenMultitouchSupport).❤️

![GitHub downloads](https://img.shields.io/github/downloads/RoversX/LaunchNext/total)
