enum UserRole {
  student,
  teacher,
  admin,
}

UserRole? userRoleFromString(String? role) {
  switch (role) {
    case 'student':
      return UserRole.student;
    case 'teacher':
      return UserRole.teacher;
    case 'admin':
      return UserRole.admin;
    default:
      return null;
  }
}
