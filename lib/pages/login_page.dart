import 'package:flutter/material.dart';
import 'package:SICAE/pages/pages.dart';
import 'package:SICAE/utils/auth_state.dart';
import 'package:SICAE/utils/database_utils.dart';

class LoginPage extends StatefulWidget {
  static const String name = '/login';
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordCorrect = true;
  bool _isLoading = false;

  Future<void> _validatePassword() async {
    if (_usernameController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      setState(() {
        _isPasswordCorrect = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _isPasswordCorrect = true;
    });

    try {
      // Intentar autenticar con la base de datos
      final user = await DatabaseUtils.authenticateUser(
        _usernameController.text.trim(),
        _passwordController.text.trim(),
      );

      if (user != null) {
        // Usuario autenticado exitosamente
        setState(() {
          _isPasswordCorrect = true;
        });
        AuthState().login();
        Navigator.pushReplacementNamed(context, ListPage.name);
      } else {
        // Verificar si es la contraseña genérica del admin
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
    } catch (e) {
      setState(() {
        _isPasswordCorrect = false;
      });
    } finally {
      setState(() {
        _isLoading = false;
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
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Usuario',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock),
                  errorText: _isPasswordCorrect
                      ? null
                      : 'Usuario o contraseña incorrectos',
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _validatePassword,
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.amber, // Color dorado
                  minimumSize: const Size(double.infinity, 50), // Más ancho
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.amber),
                        ),
                      )
                    : const Text('INGRESAR'),
              ),
              const SizedBox(height: 50),
              const Text(
                '*Ingrese sus credenciales o use la contraseña genérica del administrador',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
