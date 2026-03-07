# LaunchNext

**Ngôn ngữ**: [English](../README.md) | [中文](README.zh.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [हिन्दी](README.hi.md) | [Tiếng Việt](README.vi.md) | [Italiano](README.it.md) | [Čeština](README.cs.md)

## 📥 Tải xuống

**[Tải tại đây](https://github.com/RoversX/LaunchNext/releases/latest)** - Lấy phiên bản mới nhất

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

### LaunchNext mang lại gì
- ✅ **Nhập một cú nhấp từ Launchpad hệ thống cũ** - đọc trực tiếp cơ sở dữ liệu SQLite Launchpad gốc của bạn (`/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db`) để tái tạo hoàn hảo các thư mục hiện có, vị trí ứng dụng và bố cục
- ✅ **Trải nghiệm Launchpad cổ điển** - hoạt động chính xác như giao diện gốc được yêu thích
- ✅ **Hỗ trợ đa ngôn ngữ** - quốc tế hóa đầy đủ với tiếng Anh, tiếng Trung, tiếng Nhật, tiếng Hàn, tiếng Pháp, tiếng Tây Ban Nha, tiếng Đức, tiếng Nga, tiếng Hindi và tiếng Việt
- ✅ **Ẩn nhãn biểu tượng** - chế độ xem sạch sẽ, tối giản khi bạn không cần tên ứng dụng
- ✅ **Kích thước biểu tượng tùy chỉnh** - điều chỉnh kích thước biểu tượng theo sở thích
- ✅ **Quản lý thư mục thông minh** - tạo và sắp xếp thư mục như trước
- ✅ **Tìm kiếm tức thì và điều hướng bàn phím** - tìm ứng dụng nhanh chóng

### Những gì chúng ta đã mất trong macOS Tahoe
- ❌ Không có tổ chức ứng dụng tùy chỉnh
- ❌ Không có thư mục do người dùng tạo
- ❌ Không có tùy chỉnh kéo và thả
- ❌ Không có quản lý ứng dụng trực quan
- ❌ Nhóm phân loại bắt buộc

lưu ý rằng hầu hết README dưới đây được tạo bởi Claude AI, chưa xem xét, một số thông tin có thể không chính xác. nhưng đối với claude, bạn hoàn toàn đúng!

## Tính năng

### 🎯 **Khởi chạy ứng dụng tức thì**
- Nhấp đúp để khởi chạy ứng dụng trực tiếp
- Hỗ trợ điều hướng bàn phím đầy đủ
- Tìm kiếm nhanh như chớp với lọc thời gian thực

### 📁 **Hệ thống thư mục nâng cao**
- Tạo thư mục bằng cách kéo ứng dụng lại với nhau
- Đổi tên thư mục bằng chỉnh sửa nội tuyến
- Biểu tượng thư mục tùy chỉnh và tổ chức
- Kéo ứng dụng vào và ra một cách liền mạch

### 🔍 **Tìm kiếm thông minh**
- Khớp mờ thời gian thực
- Tìm kiếm trên tất cả ứng dụng đã cài đặt
- Phím tắt để truy cập nhanh

### 🎨 **Thiết kế giao diện hiện đại**
- **Hiệu ứng thủy tinh lỏng**: regularMaterial với bóng đổ thanh lịch
- Chế độ hiển thị toàn màn hình và cửa sổ
- Hoạt ảnh và chuyển tiếp mượt mà
- Bố cục sạch sẽ, đáp ứng

### 🔄 **Di chuyển dữ liệu liền mạch**
- **Nhập Launchpad một cú nhấp** từ cơ sở dữ liệu macOS gốc
- Khám phá và quét ứng dụng tự động
- Lưu trữ bố cục bền vững qua SwiftData
- Không mất dữ liệu trong quá trình cập nhật hệ thống

### ⚙️ **Tích hợp hệ thống**
- Ứng dụng macOS gốc
- Định vị nhận biết đa màn hình
- Hoạt động cùng với Dock và các ứng dụng hệ thống khác
- Phát hiện nhấp chuột nền (loại bỏ thông minh)

## Kiến trúc kỹ thuật

### Được xây dựng với công nghệ hiện đại
- **SwiftUI**: Khung giao diện người dùng khai báo, hiệu suất cao
- **SwiftData**: Lớp duy trì dữ liệu mạnh mẽ
- **AppKit**: Tích hợp hệ thống macOS sâu
- **SQLite3**: Đọc cơ sở dữ liệu Launchpad trực tiếp

### Lưu trữ dữ liệu
Dữ liệu ứng dụng được lưu trữ an toàn tại:
```
~/Library/Application Support/LaunchNext/Data.store
```

### Tích hợp Launchpad gốc
Đọc trực tiếp từ cơ sở dữ liệu Launchpad hệ thống:
```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## Cài đặt

### Yêu cầu
- macOS 15 (Sequoia) trở lên
- Bộ xử lý Apple Silicon hoặc Intel
- Xcode 26 (để xây dựng từ mã nguồn)

### Xây dựng từ mã nguồn

1. **Sao chép kho lưu trữ**
   ```bash
   git clone https://github.com/yourusername/LaunchNext.git
   cd LaunchNext/LaunchNext
   ```

2. **Xây dựng trình cập nhật**
   ```bash
   swift build --package-path UpdaterScripts/SwiftUpdater --configuration release --arch arm64 --arch x86_64 --product SwiftUpdater
   ```

3. **Mở trong Xcode**
   ```bash
   open LaunchNext.xcodeproj
   ```

4. **Xây dựng và chạy**
   - Chọn thiết bị đích
   - Nhấn `⌘+R` để xây dựng và chạy
   - Hoặc `⌘+B` chỉ để xây dựng

### Xây dựng dòng lệnh

**Xây dựng thông thường:**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release
```

**Xây dựng nhị phân Universal (Intel + Apple Silicon):**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

## Sử dụng

### Bắt đầu
1. **Khởi chạy đầu tiên**: LaunchNext tự động quét tất cả ứng dụng đã cài đặt
2. **Chọn**: Nhấp để chọn ứng dụng, nhấp đúp để khởi chạy
3. **Tìm kiếm**: Gõ để lọc ứng dụng ngay lập tức
4. **Tổ chức**: Kéo ứng dụng để tạo thư mục và bố cục tùy chỉnh

### Nhập Launchpad của bạn
1. Mở Cài đặt (biểu tượng bánh răng)
2. Nhấp **"Nhập Launchpad"**
3. Bố cục và thư mục hiện có của bạn được nhập tự động

### Quản lý thư mục
- **Tạo thư mục**: Kéo một ứng dụng lên ứng dụng khác
- **Đổi tên thư mục**: Nhấp vào tên thư mục
- **Thêm ứng dụng**: Kéo ứng dụng vào thư mục
- **Xóa ứng dụng**: Kéo ứng dụng ra khỏi thư mục

### Chế độ hiển thị
- **Cửa sổ**: Cửa sổ nổi với các góc bo tròn
- **Toàn màn hình**: Chế độ toàn màn hình để có khả năng hiển thị tối đa
- Chuyển đổi chế độ trong Cài đặt

## Cấu trúc dự án

```
LaunchNext/
├── LaunchpadApp.swift          # Điểm vào ứng dụng
├── AppStore.swift              # Quản lý trạng thái & dữ liệu
├── LaunchpadView.swift         # Giao diện chính
├── LaunchpadItemButton.swift   # Thành phần biểu tượng ứng dụng
├── FolderView.swift           # Giao diện thư mục
├── SettingsView.swift         # Bảng cài đặt
├── NativeLaunchpadImporter.swift # Hệ thống nhập dữ liệu
├── Extensions.swift           # Tiện ích chia sẻ
├── Animations.swift           # Định nghĩa hoạt ảnh
├── AppInfo.swift              # Mô hình dữ liệu ứng dụng
├── FolderInfo.swift           # Mô hình dữ liệu thư mục
├── GeometryUtils.swift        # Tính toán bố cục
└── AppCacheManager.swift      # Tối ưu hóa hiệu suất
```

## Tại sao chọn LaunchNext?

### vs. Giao diện "Ứng dụng" của Apple
| Tính năng | Ứng dụng (Tahoe) | LaunchNext |
|---------|---------------------|------------|
| Tổ chức tùy chỉnh | ❌ | ✅ |
| Thư mục người dùng | ❌ | ✅ |
| Kéo & Thả | ❌ | ✅ |
| Quản lý trực quan | ❌ | ✅ |
| Nhập dữ liệu hiện có | ❌ | ✅ |
| Hiệu suất | Chậm | Nhanh |

### vs. Các lựa chọn thay thế Launchpad khác
- **Tích hợp gốc**: Đọc cơ sở dữ liệu Launchpad trực tiếp
- **Kiến trúc hiện đại**: Được xây dựng với SwiftUI/SwiftData mới nhất
- **Không phụ thuộc**: Swift thuần túy, không có thư viện bên ngoài
- **Phát triển tích cực**: Cập nhật và cải tiến thường xuyên
- **Thiết kế thủy tinh lỏng**: Hiệu ứng thị giác cao cấp

## Tính năng nâng cao

### Tương tác nền thông minh
- Phát hiện nhấp chuột thông minh ngăn ngừa loại bỏ tình cờ
- Xử lý cử chỉ nhận biết ngữ cảnh
- Bảo vệ trường tìm kiếm

### Tối ưu hóa hiệu suất
- **Bộ nhớ đệm biểu tượng**: Bộ nhớ đệm hình ảnh thông minh cho cuộn mượt
- **Tải chậm**: Sử dụng bộ nhớ hiệu quả
- **Quét nền**: Khám phá ứng dụng không chặn

### Hỗ trợ đa màn hình
- Phát hiện màn hình tự động
- Định vị cho từng màn hình
- Quy trình làm việc đa màn hình liền mạch

## Vấn đề đã biết

> **Trạng thái phát triển hiện tại**
> - 🔄 **Hành vi cuộn**: Có thể không ổn định trong một số tình huống, đặc biệt với cử chỉ nhanh
> - 🎯 **Tạo thư mục**: Phát hiện kéo và thả để tạo thư mục đôi khi không nhất quán
> - 🛠️ **Phát triển tích cực**: Những vấn đề này đang được giải quyết tích cực trong các bản phát hành sắp tới

## Khắc phục sự cố

### Vấn đề thường gặp

**Q: Ứng dụng không khởi động?**
A: Đảm bảo macOS 15.0+ và kiểm tra quyền hệ thống.

**Q: Thiếu nút nhập?**
A: Xác minh SettingsView.swift bao gồm chức năng nhập.

**Q: Tìm kiếm không hoạt động?**
A: Thử quét lại ứng dụng hoặc đặt lại dữ liệu ứng dụng trong Cài đặt.

**Q: Vấn đề hiệu suất?**
A: Kiểm tra cài đặt bộ nhớ đệm biểu tượng và khởi động lại ứng dụng.

## Đóng góp

Chúng tôi hoan nghênh đóng góp! Vui lòng:

1. Fork kho lưu trữ
2. Tạo nhánh tính năng (`git checkout -b feature/amazing-feature`)
3. Commit thay đổi (`git commit -m 'Add amazing feature'`)
4. Push lên nhánh (`git push origin feature/amazing-feature`)
5. Mở Pull Request

### Hướng dẫn phát triển
- Tuân theo quy ước phong cách Swift
- Thêm bình luận có ý nghĩa cho logic phức tạp
- Kiểm tra trên nhiều phiên bản macOS
- Duy trì khả năng tương thích ngược

## Tương lai của quản lý ứng dụng

Khi Apple di chuyển ra khỏi các giao diện có thể tùy chỉnh, LaunchNext đại diện cho cam kết của cộng đồng đối với kiểm soát người dùng và cá nhân hóa. Chúng tôi tin rằng người dùng nên quyết định cách tổ chức không gian làm việc kỹ thuật số của họ.

**LaunchNext** không chỉ là một sự thay thế Launchpad—nó là một tuyên bố rằng lựa chọn của người dùng quan trọng.

---

**LaunchNext** - Lấy lại Trình khởi chạy ứng dụng của bạn 🚀

*Được xây dựng cho người dùng macOS từ chối thỏa hiệp về tùy chỉnh.*

## Công cụ phát triển

Dự án này được phát triển với sự hỗ trợ từ:

- Claude Code
- Cursor
- OpenAI Codex Cli