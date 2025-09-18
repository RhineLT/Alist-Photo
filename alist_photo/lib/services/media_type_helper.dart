import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'log_service.dart';

/// 动态照片供应商类型
enum DynamicVendor { apple, xiaomi, google, unknown }

/// 本地动态照片检测结果
class LocalDynamicInfo {
  final bool isDynamic;
  final DynamicVendor vendor; // apple/xiaomi/google/unknown
  final File imageFile; // 用于显示的静态图
  final File? videoFile; // 若为侧车视频则返回（长按播放）
  final bool isEmbeddedMotion; // 是否为嵌入式 Motion Photo（无侧车视频）

  const LocalDynamicInfo({
    required this.isDynamic,
    required this.vendor,
    required this.imageFile,
    this.videoFile,
    this.isEmbeddedMotion = false,
  });
}

class MediaType {
  static const Set<String> imageExts = {
    'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'tiff', 'ico', 'svg', 'heic', 'heif'
  };
  static const Set<String> videoExts = {
    'mp4', 'avi', 'mov', 'wmv', 'flv', 'webm', 'mkv', 'm4v', '3gp', 'ts', 'm3u8', 'mp4v'
  };

  static bool isImage(String fileName) {
    final ext = _ext(fileName);
    return imageExts.contains(ext);
  }
  
  static bool isVideo(String fileName) {
    final ext = _ext(fileName);
    return videoExts.contains(ext);
  }
  
  /// 旧接口：不再仅凭扩展名判断 Live Photo，保持兼容但仅返回是否可能为动态（heic/live）
  static bool isLivePhoto(String fileName) {
    final ext = _ext(fileName);
    // 苹果 Live Photo 常见静态图扩展：heic/heif/jpg
    return ext == 'heic' || ext == 'heif' || ext == 'live';
  }
  
  static bool isMediaFile(String fileName) {
    return isImage(fileName) || isVideo(fileName) || isLivePhoto(fileName);
  }
  
  static String getMediaType(String fileName) {
    if (isVideo(fileName)) return 'video';
    if (isLivePhoto(fileName)) return 'live_photo';
    if (isImage(fileName)) return 'image';
    return 'unknown';
  }
  
  /// 获取视频文件的缩略图URL（如果支持的话）
  static String getVideoThumbnailUrl(String videoUrl) {
    // Alist可能支持视频缩略图，这里可以根据实际API调整
    return videoUrl.replaceFirst('/d/', '/p/').replaceFirst(RegExp(r'\.[^.]+$'), '_thumb.jpg');
  }

  /// 针对“本地已存在的图片文件”进行动态照片检测
  /// 规则：
  /// - Apple Live Photo: 同目录下同名 .mov（区分大小写不敏感），静态图可能是 .heic/.heif/.jpg/.jpeg
  /// - 小米动态照片（侧车视频）: 同名 .mp4/.mp4v/.mov 存在
  /// - 嵌入式 Motion Photo: jpg/jpeg 内含 MotionPhoto/XMP 标记（不提供视频侧车）
  static Future<LocalDynamicInfo> detectLocalDynamic(File imageFile) async {
    final fileName = p.basename(imageFile.path);
    final dir = imageFile.parent;
    final base = _basenameNoExt(fileName);
    final imageExt = _ext(fileName);

    // 仅对图片尝试动态检测
    if (!isImage(fileName)) {
      return LocalDynamicInfo(
        isDynamic: false,
        vendor: DynamicVendor.unknown,
        imageFile: imageFile,
      );
    }

    // 1) Apple Live Photo: sidecar .mov
    final appleCandidate = File(p.join(dir.path, '$base.mov'));
    if (await appleCandidate.exists()) {
      LogService.instance.info('Apple Live Photo detected (sidecar MOV)', 'MediaType', {
        'image': imageFile.path,
        'video': appleCandidate.path,
      });
      return LocalDynamicInfo(
        isDynamic: true,
        vendor: DynamicVendor.apple,
        imageFile: imageFile,
        videoFile: appleCandidate,
      );
    }

    // 2) Xiaomi dynamic (common sidecar)
    final sidecarExts = ['mp4', 'mp4v', 'mov'];
    for (final ext in sidecarExts) {
      final f = File(p.join(dir.path, '$base.$ext'));
      if (await f.exists()) {
        LogService.instance.info('Xiaomi dynamic photo detected (sidecar $ext)', 'MediaType', {
          'image': imageFile.path,
          'video': f.path,
        });
        return LocalDynamicInfo(
          isDynamic: true,
          vendor: DynamicVendor.xiaomi,
          imageFile: imageFile,
          videoFile: f,
        );
      }
    }

    // 一些机型会在同目录使用变化名，如 "IMG_xxx_VIDEO.mp4"，简单再尝试一个常见后缀
    final alt = File(p.join(dir.path, '${base}_VIDEO.mp4'));
    if (await alt.exists()) {
      LogService.instance.info('Xiaomi dynamic photo detected (alt suffix _VIDEO.mp4)', 'MediaType', {
        'image': imageFile.path,
        'video': alt.path,
      });
      return LocalDynamicInfo(
        isDynamic: true,
        vendor: DynamicVendor.xiaomi,
        imageFile: imageFile,
        videoFile: alt,
      );
    }

    // 3) Embedded Motion Photo (Google/Xiaomi): 在 jpg/jpeg 中查找 XMP/MotionPhoto 标记
    if (imageExt == 'jpg' || imageExt == 'jpeg') {
      final embedded = await _looksLikeEmbeddedMotionPhoto(imageFile);
      if (embedded) {
        LogService.instance.info('Embedded Motion Photo detected (no sidecar)', 'MediaType', {
          'image': imageFile.path,
        });
        return LocalDynamicInfo(
          isDynamic: true,
          vendor: DynamicVendor.google,
          imageFile: imageFile,
          videoFile: null,
          isEmbeddedMotion: true,
        );
      }
    }

    // 默认：非动态
    LogService.instance.debug('Static image (no dynamic pair found)', 'MediaType', {
      'image': imageFile.path,
    });
    return LocalDynamicInfo(
      isDynamic: false,
      vendor: DynamicVendor.unknown,
      imageFile: imageFile,
    );
  }

  // 简单判断 JPEG 内是否包含 MotionPhoto/XMP 相关标记，避免全量解析
  static Future<bool> _looksLikeEmbeddedMotionPhoto(File jpg) async {
    try {
  final stat = await jpg.stat();
  // 读取前 128KB 与后 256KB 进行文本匹配
  final raf = await jpg.open();
  final headLen = stat.size < 128 * 1024 ? stat.size : 128 * 1024;
      final head = await raf.read(headLen);
      // 末尾读取
      int tailLen = 256 * 1024;
  if (stat.size < tailLen) tailLen = stat.size;
  await raf.setPosition(stat.size - tailLen);
      final tail = await raf.read(tailLen);
      await raf.close();

      bool containsTag(List<int> bytes) {
        final s = String.fromCharCodes(bytes);
        // 常见关键词
        const keys = [
          'GCamera:MotionPhoto',
          'MotionPhoto',
          'MicroVideo',
          'MotionPhotoVersion',
          'Camera:MotionPhoto',
          'XMP',
        ];
        for (final k in keys) {
          if (s.contains(k)) return true;
        }
        return false;
      }

      return containsTag(head) || containsTag(tail);
    } catch (e) {
      LogService.instance.warning('Embedded motion check failed: $e', 'MediaType', {
        'path': jpg.path,
      });
      return false;
    }
  }

  /// 基于 XMP 中的 MicroVideoOffset 将嵌入式视频从 JPEG 中提取为临时 MP4 文件
  /// 行业通用做法：
  /// - 读取 XMP，解析 (GCamera:)MicroVideoOffset；
  /// - 按 videoStart = fileSize - offset 定位视频起始；
  /// - 校验起始附近存在 'ftyp' box；
  /// - 复制 [videoStart..EOF] 为 .mp4 临时文件。
  static Future<File?> extractEmbeddedMicroVideo(File jpg) async {
    try {
      final stat = await jpg.stat();
      final fileSize = stat.size;
      final raf = await jpg.open();
      // 读取头部较大块以解析 XMP（APP1 常见在头部），以及尾部一小块备用
      final headLen = fileSize < 512 * 1024 ? fileSize : 512 * 1024;
      final head = await raf.read(headLen);

      int? offset; // MicroVideoOffset
      String headStr;
      try {
        headStr = String.fromCharCodes(head);
      } catch (_) {
        headStr = '';
      }

      if (headStr.isNotEmpty) {
        final re = RegExp(r'(?:GCamera:)?MicroVideoOffset[^0-9]*([0-9]+)');
        final m = re.firstMatch(headStr);
        if (m != null) {
          offset = int.tryParse(m.group(1)!);
        }
      }

      // 若头部未找到，尝试尾部（某些实现也会在尾部留痕）
      if (offset == null) {
        final tailLen = fileSize < 256 * 1024 ? fileSize : 256 * 1024;
        await raf.setPosition(fileSize - tailLen);
        final tail = await raf.read(tailLen);
        String tailStr;
        try { tailStr = String.fromCharCodes(tail); } catch (_) { tailStr = ''; }
        if (tailStr.isNotEmpty) {
          final re = RegExp(r'(?:GCamera:)?MicroVideoOffset[^0-9]*([0-9]+)');
          final m = re.firstMatch(tailStr);
          if (m != null) {
            offset = int.tryParse(m.group(1)!);
          }
        }
      }

      if (offset == null || offset <= 0 || offset >= fileSize) {
        await raf.close();
        LogService.instance.warning('No valid MicroVideoOffset found', 'MediaType', {
          'path': jpg.path,
        });
        return null;
      }

      int start = fileSize - offset; // 常见定义：从文件尾部回退 offset 为视频起点
      if (start < 0) start = 0;

      // 校验 MP4 ftyp
      await raf.setPosition(start);
      final probe = await raf.read(4096); // 取 4KB 探测 ftyp
      int? ftypIndex;
      for (int i = 0; i <= probe.length - 4; i++) {
        if (probe[i] == 0x66 && probe[i + 1] == 0x74 && probe[i + 2] == 0x79 && probe[i + 3] == 0x70) {
          // 'f' 't' 'y' 'p'
          ftypIndex = i;
          break;
        }
      }
      if (ftypIndex == null) {
        await raf.close();
        LogService.instance.warning('MP4 ftyp not found near expected start', 'MediaType', {
          'path': jpg.path,
          'start': start,
        });
        return null;
      }

      final videoStart = start + (ftypIndex - 4 >= 0 ? ftypIndex - 4 : 0);
      if (videoStart < 0 || videoStart >= fileSize) {
        await raf.close();
        LogService.instance.warning('Computed videoStart out of range', 'MediaType', {
          'videoStart': videoStart,
          'fileSize': fileSize,
        });
        return null;
      }

      // 将 [videoStart..EOF] 写入临时 mp4
      final tmpDir = await getTemporaryDirectory();
      final base = p.basenameWithoutExtension(jpg.path);
      final outPath = p.join(tmpDir.path, '${base}_motion.mp4');
      final out = File(outPath);
      if (await out.exists()) { try { await out.delete(); } catch (_) {} }

      final outRaf = await out.open(mode: FileMode.write);
      const chunk = 1024 * 1024;
      int pos = videoStart;
      await raf.setPosition(videoStart);
      while (pos < fileSize) {
        final toRead = (fileSize - pos) < chunk ? (fileSize - pos) : chunk;
        final data = await raf.read(toRead);
        if (data.isEmpty) break;
        await outRaf.writeFrom(data);
        pos += data.length;
      }
      await outRaf.close();
      await raf.close();

      LogService.instance.info('Extracted embedded motion video', 'MediaType', {
        'jpg': jpg.path,
        'mp4': out.path,
      });
      return out;
    } catch (e) {
      LogService.instance.error('extractEmbeddedMicroVideo failed: $e', 'MediaType', {
        'path': jpg.path,
      });
      return null;
    }
  }

  static String _ext(String fileName) =>
      fileName.toLowerCase().split('.').last;

  static String _basenameNoExt(String fileName) {
    final ext = _ext(fileName);
    if (fileName.length > ext.length + 1) {
      return fileName.substring(0, fileName.length - ext.length - 1);
    }
    return fileName;
  }
}