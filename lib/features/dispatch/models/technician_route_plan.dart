class TechnicianRoutePlan {
  const TechnicianRoutePlan({
    required this.technicianId,
    required this.jobIds,
    required this.estimatedKm,
    required this.estimatedDriveMinutes,
    required this.score,
  });

  final String technicianId;
  final List<String> jobIds;
  final double estimatedKm;
  final int estimatedDriveMinutes;
  final double score;
}
