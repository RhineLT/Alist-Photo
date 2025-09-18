class MediaType {
  static bool isImage(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'tiff', 'ico', 'svg'].contains(extension);
  }
  
  static bool isVideo(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    return ['mp4', 'avi', 'mov', 'wmv', 'flv', 'webm', 'mkv', 'm4v', '3gp', 'ts', 'm3u8'].contains(extension);
  }
  
  static bool isLivePhoto(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    // 小米动态照片格式
    if (extension == 'jpg' || extension == 'jpeg') {
      // 需要检查是否有对应的视频文件
      return false; // 这里需要通过API检查伴随文件
    }
    // 苹果Live Photo格式 - 通常是HEIC+MOV
    return extension == 'heic' || extension == 'live';
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
}