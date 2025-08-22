import 'package:flutter/material.dart';
import 'package:SICAE/pages/pages.dart';
import 'package:SICAE/utils/auth_state.dart';

class LoginPage extends StatefulWidget {
  static const String name = '/login';
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _passwordController = TextEditingController();
  bool _isPasswordCorrect = true;

  void _validatePassword() {
    if (_passwordController.text == 'epo26pass') {
      setState(() {
        _isPasswordCorrect = true;
      });
      AuthState().login();
      Navigator.pushReplacementNamed(context, ListPage.name);
    } else {
      setState(() {
        _isPasswordCorrect = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/logo26.png',
                height: 300,
              ),
              const SizedBox(height: 20),
              const Text(
                'Bienvenido',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  border: const OutlineInputBorder(),
                  errorText:
                      _isPasswordCorrect ? null : 'Contraseña incorrecta',
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _validatePassword,
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.amber, // Color dorado
                  minimumSize: const Size(double.infinity, 50), // Más ancho
                ),
                child: const Text('INGRESAR'),
              ),
              const SizedBox(height: 50),
              const Text(
                '*Solicite la contraseña al administrador',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }
}
