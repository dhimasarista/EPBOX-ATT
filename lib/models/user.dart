class User {
  final String id;
  final String name;
  final String email;
  final String? role;
  // Tambahkan field lain jika perlu di masa depan
  // final String? nik;
  // final String? position;

  User({required this.id, required this.name, required this.email, this.role});

  // Factory constructor untuk membuat User dari JSON
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']
          .toString(), // TSID dari EPBOX-PRIME seringkali turun sebagai String
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']
          ?.toString(), // role bisa null karena di EPBOX-PRIME pakai role_id
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'email': email, 'role': role};
  }
}
