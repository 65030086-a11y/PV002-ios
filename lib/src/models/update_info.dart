// Models for the OTA software-update subsystem.

// ---------------------------------------------------------------------------
// Version info — returned by :update_check
// ---------------------------------------------------------------------------

class UpdateVersionInfo {
  const UpdateVersionInfo({
    required this.version,
    this.updatedAt,
    this.changelog,
  });

  final String   version;
  final String?  updatedAt;
  final String?  changelog;

  bool get hasDate => updatedAt != null && updatedAt!.isNotEmpty;

  DateTime? get updatedAtDate =>
      hasDate ? DateTime.tryParse(updatedAt!) : null;

  factory UpdateVersionInfo.fromJson(Map<String, dynamic> json) =>
      UpdateVersionInfo(
        version:   json['version']    as String? ?? 'unknown',
        updatedAt: json['updated_at'] as String?,
        changelog: json['changelog']  as String?,
      );
}

// ---------------------------------------------------------------------------
// Update status — returned by :update_status
// ---------------------------------------------------------------------------

class UpdateStatus {
  const UpdateStatus({
    required this.stage,
    required this.progress,
    required this.message,
    this.error,
  });

  const UpdateStatus.idle()
      : stage    = 'idle',
        progress = 0,
        message  = '',
        error    = null;

  final String  stage;
  final int     progress;   // 0–100
  final String  message;
  final String? error;

  bool get isIdle       => stage == 'idle';
  bool get isActive     => !isIdle && !isFailed;
  bool get isFailed     => stage == 'failed';
  bool get isRestarting => stage == 'restarting';
  bool get needsPin =>
      stage == 'idle' || stage == 'failed';

  factory UpdateStatus.fromJson(Map<String, dynamic> json) => UpdateStatus(
        stage:    json['stage']    as String? ?? 'idle',
        progress: (json['progress'] as num?)?.toInt() ?? 0,
        message:  json['message']  as String? ?? '',
        error:    json['error']    as String?,
      );
}

// ---------------------------------------------------------------------------
// Prepare-upload result — returned by :update_prepare_upload
// ---------------------------------------------------------------------------

class PrepareUploadResult {
  const PrepareUploadResult({
    required this.port,
    required this.token,
    required this.expiresIn,
  });

  final int    port;
  final String token;
  final int    expiresIn;   // seconds

  factory PrepareUploadResult.fromJson(Map<String, dynamic> json) =>
      PrepareUploadResult(
        port:      (json['port']       as num).toInt(),
        token:     json['token']       as String,
        expiresIn: (json['expires_in'] as num?)?.toInt() ?? 120,
      );
}
