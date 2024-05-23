import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  initializeDateFormatting('pt_BR', null);
  runApp(MaterialApp(
    title: 'Meu Ponto',
    theme: ThemeData(
      primaryColor: Colors.blue,
      scaffoldBackgroundColor: Colors.white,
      textTheme: TextTheme(
        bodyText1: TextStyle(color: Colors.black),
        bodyText2: TextStyle(color: Colors.black),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: MaterialStateProperty.all<Color>(Colors.blue),
          foregroundColor: MaterialStateProperty.all<Color>(Colors.black),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: Colors.blue,
      ),
    ),
    home: LoginPage(),
  ));
}

class MyClock extends StatefulWidget {
  @override
  _MyClockState createState() => _MyClockState();
}

class _MyClockState extends State<MyClock> {
  Map<String, Map<String, List<String>>> recordsByDate = {};

  @override
  void initState() {
    super.initState();
    _loadRecords();
    _checkNTP();
  }

  void _checkNTP() async {
    try {
      Socket socket = await Socket.connect('time.google.com', 123);
      List<int> msg = [0x1B, for (int i = 0; i < 47; i++) 0];
      socket.add(msg);
      List<int> response = [];
      await for (var data in socket) {
        response.addAll(data);
        if (response.length >= 48) {
          break;
        }
      }
      socket.close();
      int secondsSince1900 = 0;
      for (int i = 0; i < 4; i++) {
        secondsSince1900 = (secondsSince1900 << 8) + response[43 + i];
      }
      DateTime ntpTime =
          DateTime.utc(1900, 1, 1).add(Duration(seconds: secondsSince1900));
      DateTime now = DateTime.now();
      Duration difference = now.difference(ntpTime);
      if (difference.inMinutes.abs() > 1) {
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text('Erro de sincronização'),
              content: Text(
                  'A hora do dispositivo não está sincronizada. Por favor, corrija a data e hora.'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: Text('OK'),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      print('Erro ao obter a hora do NTP: $e');
    }
  }

  Future<void> _loadRecords() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    recordsByDate = Map<String, Map<String, List<String>>>.from(
      (prefs.getString('recordsByDate') ?? '{}')
          .split(',')
          .fold<Map<String, Map<String, List<String>>>>(
        {},
        (map, monthEntry) {
          final parts = monthEntry.split(':');
          final monthYear = parts[0].trim();
          final daysData = parts[1].trim();
          map[monthYear] = Map<String, List<String>>.from(
            daysData.split(';').fold<Map<String, List<String>>>(
              {},
              (daysMap, dayEntry) {
                final dayParts = dayEntry.split('|');
                final day = dayParts[0].trim();
                final records = dayParts[1]
                    .split(',')
                    .map((record) => record.trim())
                    .toList();
                daysMap[day] = records;
                return daysMap;
              },
            ),
          );
          return map;
        },
      ),
    );
  }

  void _saveRecords() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'recordsByDate',
      recordsByDate.entries
          .map((entry) =>
              '${entry.key}: ${entry.value.entries.map((dayEntry) => '${dayEntry.key}|${dayEntry.value.join(',')}').join(';')}')
          .join(','),
    );
  }

  void _clockInPressed() {
    _addRecord('Entrada');
  }

  void _lunchStartPressed() {
    _addRecord('Almoço');
  }

  void _lunchEndPressed() {
    _addRecord('Volta Almoço');
  }

  void _clockOutPressed() {
    _addRecord('Saída');
  }

  void _addRecord(String type) {
    DateTime now = DateTime.now();
    String date = '${now.day}/${now.month}/${now.year}';
    String monthYear = '${now.month}/${now.year}';

    recordsByDate[monthYear] ??= {};
    recordsByDate[monthYear]![date] ??= [];

    if (recordsByDate[monthYear]![date]!.length < 4) {
      setState(() {
        recordsByDate[monthYear]![date]!.add('$type ${_getCurrentTime()}');
        _saveRecords();
      });
    }
  }

  String _getCurrentTime() {
    DateTime localNow = DateTime.now();
    DateTime brTime = localNow.toUtc().subtract(Duration(hours: 3));

    String hour = '${brTime.hour}'.padLeft(2, '0');
    String minute = '${brTime.minute}'.padLeft(2, '0');
    String second = '${brTime.second}'.padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  List<String> _getMonthsList() {
    return recordsByDate.keys.toList()..sort((a, b) => b.compareTo(a));
  }

  List<String> _getDaysForMonthYear(String monthYear) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final dayOfWeekFormat = DateFormat('EEEE', 'pt_BR');
    final records = recordsByDate[monthYear] ?? {};
    return records.entries.map((entry) {
      final day = entry.key;
      final dayOfWeek = dayOfWeekFormat.format(dateFormat.parse(day));
      final markings = entry.value.map((marking) {
        final parts = marking.split(':');
        final type = parts[0].trim();
        final time = parts[1].trim();
        return '$type:$time';
      }).toList();
      return '$day ($dayOfWeek):\n${markings.join('\n')}';
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Meu Ponto'),
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => LoginPage()),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FloatingActionButton(
                  onPressed: _clockInPressed,
                  tooltip: 'Clique para registrar a entrada',
                  child: Icon(Icons.directions_walk),
                ),
                SizedBox(width: 10),
                FloatingActionButton(
                  onPressed: _lunchStartPressed,
                  tooltip: 'Clique para registrar o início do almoço',
                  child: Icon(Icons.restaurant_menu),
                ),
                SizedBox(width: 10),
                FloatingActionButton(
                  onPressed: _lunchEndPressed,
                  tooltip: 'Clique para registrar a volta do almoço',
                  child: Icon(Icons.access_time),
                ),
                SizedBox(width: 10),
                FloatingActionButton(
                  onPressed: _clockOutPressed,
                  tooltip: 'Clique para registrar a saída',
                  child: Icon(Icons.exit_to_app),
                ),
              ],
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TimeClockReportsScreen(recordsByDate),
                  ),
                );
              },
              child: Text('Ver Relatórios'),
            ),
          ],
        ),
      ),
    );
  }
}

class TimeClockReportsScreen extends StatelessWidget {
  final Map<String, Map<String, List<String>>> recordsByDate;

  TimeClockReportsScreen(this.recordsByDate);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Relatórios de Ponto'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _buildReports(),
        ),
      ),
    );
  }

  List<Widget> _buildReports() {
    List<Widget> reportWidgets = [];

    recordsByDate.forEach((monthYear, records) {
      List<String> daysList = records.keys.toList()..sort();

      // Obtenha o nome do mês a partir do mês/ano no formato "MM/yyyy"
      final monthYearParts = monthYear.split('/');
      final month = int.parse(monthYearParts[0]);
      final year = int.parse(monthYearParts[1]);
      final monthName =
          DateFormat('MMMM', 'pt_BR').format(DateTime(year, month));

      reportWidgets.add(
        Padding(
          padding: EdgeInsets.only(bottom: 20.0),
          child: ExpansionTile(
            title: Text(
              'Relatório de ${monthName.toUpperCase()}/$year',
              style: TextStyle(
                fontSize: 18.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            children: daysList.map((day) {
              List<String> dayRecords = records[day]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dia: $day (${dayRecords.length} registros)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 5.0),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: dayRecords.map((record) {
                      return Text(' - $record');
                    }).toList(),
                  ),
                  SizedBox(height: 10.0),
                ],
              );
            }).toList(),
          ),
        ),
      );
    });

    return reportWidgets;
  }
}

class LoginPage extends StatelessWidget {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Login'),
      ),
      body: Padding(
        padding: EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _usernameController,
              decoration: InputDecoration(labelText: 'Usuário'),
            ),
            SizedBox(height: 20),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(labelText: 'Senha'),
              obscureText: true,
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                if (_usernameController.text == 'admin' &&
                    _passwordController.text == 'admin') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => MyClock()),
                  );
                } else {
                  showDialog(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: Text('Erro de autenticação'),
                        content: Text('Usuário ou senha incorretos.'),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            child: Text('OK'),
                          ),
                        ],
                      );
                    },
                  );
                }
              },
              child: Text('Entrar'),
            ),
          ],
        ),
      ),
    );
  }
}
