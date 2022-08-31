import 'dart:math';
import 'package:flutter_shake_animated/flutter_shake_animated.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class QuizData {
  final int responseCode;
  final String category;
  final String type;
  final String difficulty;
  final String question;
  final String correctAnswer;
  final List<String> incorrectAnswers;

  const QuizData({
    required this.responseCode,
    required this.category,
    required this.type,
    required this.difficulty,
    required this.question,
    required this.correctAnswer,
    required this.incorrectAnswers,
  });

  factory QuizData.fromJson(Map<String, dynamic> json) {
    final results = json["results"][0];
    return QuizData(
      responseCode: json['response_code'],
      category: utf8.decode(base64Decode(results["category"])),
      type: utf8.decode(base64Decode(results["type"])),
      difficulty: utf8.decode(base64Decode(results["difficulty"])),
      question: utf8.decode(base64Decode(results["question"])),
      correctAnswer: utf8.decode(base64Decode(results["correct_answer"])),
      incorrectAnswers: results["incorrect_answers"]
          .map<String>((answer) => utf8.decode(base64Decode(answer.toString())))
          .toList(),
    );
  }
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trivia flutter thing',
      theme: ThemeData(
        primarySwatch: Colors.amber,
      ),
      home: const Quiz(),
    );
  }
}

class Quiz extends StatefulWidget {
  const Quiz({Key? key}) : super(key: key);

  @override
  State<Quiz> createState() => _QuizState();
}

class _QuizState extends State<Quiz> {
  late Future<QuizData?> _quizFuture;
  late QuizData _currentQuiz;
  late List<String> _currentOptions;

  Map<String, String>? _categoriesMap; //name, id
  Map<String, String>? _categoriesCount; //id, count
  int? _selectedAnswer;
  var _wrongShakePlay = false;
  final _wrongShakeDuration = const Duration(milliseconds: 300);
  String? _category;
  String? _token;

  @override
  initState() {
    super.initState();
    _quizFuture = _getQuiz();
    _setCategories();
    _setCategoriesCount();
  }

  //all questions answered in category
  void _endOfQuestions() {
    _resetGame();
  }

  //fetch all possible categories and save them as a map
  void _setCategories() async {
    var response =
        await http.get(Uri.https('opentdb.com', '/api_category.php'));
    if (response.statusCode == 200) {
      final data = {
        for (var i in jsonDecode(response.body)["trivia_categories"])
          i["name"].toString(): i["id"].toString()
      };
      setState(() {
        _categoriesMap = data;
      });
    } else {
      throw Exception('Failed to load categories');
    }
  }

  //fetch all possible categories and save them as a map
  void _setCategoriesCount() async {
    var response =
        await http.get(Uri.https('opentdb.com', '/api_count_global.php'));
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final data = {
        for (var i in json["categories"].keys)
          i.toString():
              json["categories"][i]["total_num_of_questions"].toString()
      };
      data["overall"] = json["overall"]["total_num_of_questions"].toString();
      setState(() {
        _categoriesCount = data;
      });
    } else {
      throw Exception('Failed to load categories counts');
    }
  }

  //fetch new session token and save it to _token
  Future _resetToken() async {
    var response = await http.get(Uri.https('opentdb.com', '/api_token.php', {
      "command": "request",
    }));
    if (response.statusCode == 200) {
      _token = jsonDecode(response.body)["token"];
    } else {
      throw Exception('Failed to load token');
    }
  }

  //the session token is reset and a new question is made
  _resetGame() async {
    await _resetToken();
    _newQuestion();
  }

  //fetches quiz data from the database
  Future<QuizData?> _getQuiz() async {
    //just to make sure it exists
    if (_token == null) {
      await _resetToken();
    }

    var url = Uri.https('opentdb.com', '/api.php', {
      "amount": "1",
      "category": _category,
      "difficulty": "easy",
      // "type": "multiple", it works for any type
      "encode": "base64",
      "token": _token,
    });
    var response = await http.get(url);
    if (response.statusCode == 200) {
      final quizDataJson = jsonDecode(response.body);
      if (quizDataJson["response_code"] == 4) {
        _endOfQuestions();
        return null;
      } else {
        var data = QuizData.fromJson(quizDataJson);
        return data;
      }
    } else {
      throw Exception('Failed to load quiz');
    }
  }

  void _newQuestion({force = false}) {
    if (!force &&
        (_selectedAnswer == null ||
            _currentOptions[_selectedAnswer!] != _currentQuiz.correctAnswer)) {
      setState(() {
        _wrongShakePlay = true;
      });
      Future.delayed(_wrongShakeDuration, () {
        setState(() {
          _wrongShakePlay = false;
        });
      });
      return;
    }

    setState(() {
      _quizFuture = _getQuiz();
      _selectedAnswer = null;
    });
  }

  Widget _quizOption(String option, int index) {
    return ListTile(
      leading: Icon(
          _selectedAnswer == index ? Icons.priority_high : Icons.question_mark),
      onTap: () {
        setState(() {
          _selectedAnswer = index;
        });
      },
      title: Text(option),
      tileColor:
          _selectedAnswer == index ? Theme.of(context).primaryColorDark : null,
    );
  }

  Widget _buildQuiz(QuizData quiz) {
    _currentQuiz = quiz;
    final options = [...quiz.incorrectAnswers, quiz.correctAnswer]
      ..shuffle(Random(quiz.question.hashCode));
    _currentOptions = options;
    List<Widget> optionsWidgets = [];
    for (var i = 0; i < options.length; i++) {
      optionsWidgets.add(_quizOption(options[i], i));
    }
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(16.0),
          child: Text(
            quiz.question,
            style: const TextStyle(fontSize: 30),
          ),
        ),
        ...optionsWidgets
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_categoriesMap != null
            ? _categoriesMap!.keys.firstWhere(
                (element) => _categoriesMap![element] == _category,
                orElse: () => "All categories")
            : "Loading..."),
        actions: [
          IconButton(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) {
                    return Scaffold(
                      appBar: AppBar(
                        title: const Text("About"),
                      ),
                      body: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: const [
                            Text("Questions from Open trivial database"),
                            Text("Made by Pesopes")
                          ],
                        ),
                      ),
                    );
                  },
                ));
              },
              icon: const Icon(Icons.info))
        ],
      ),
      body: Center(
        child: FutureBuilder<QuizData?>(
            future: _quizFuture,
            builder: (BuildContext context, AsyncSnapshot<QuizData?> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator();
              } else if (snapshot.connectionState == ConnectionState.done) {
                if (snapshot.hasError) {
                  return const Text('Error');
                } else if (snapshot.hasData) {
                  return _buildQuiz(snapshot.data!);
                } else {
                  return Center(
                    child: Column(
                      children: [
                        const Text('No more questions :)'),
                        TextButton(
                            onPressed: _resetGame,
                            child: const Text("Reset questions"))
                      ],
                    ),
                  );
                }
              } else {
                return Text("${snapshot.connectionState}");
              }
            }),
      ),
      drawer: (_categoriesMap != null && _categoriesCount != null)
          ? Drawer(
              backgroundColor: Theme.of(context).backgroundColor,
              child: ListView(
                children: [
                  DrawerHeader(
                    decoration:
                        BoxDecoration(color: Theme.of(context).primaryColor),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text(
                          "Select category",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                          ),
                        ),
                        Icon(
                          Icons.category,
                          size: 70.0,
                        )
                      ],
                    ),
                  ),
                  ...[null, ..._categoriesMap!.keys]
                      .map((categoryName) => ListTile(
                            title: Text((categoryName ?? "All categories") +
                                (" (${_categoriesCount![_categoriesMap![categoryName]] ?? _categoriesCount!["overall"]!})")),
                            onTap: () {
                              setState(() {
                                _category = _categoriesMap?[categoryName];
                                _newQuestion(force: true);
                                Navigator.pop(context);
                              });
                            },
                          ))
                      .toList()
                ],
              ))
          : null,
      floatingActionButton: ShakeWidget(
        autoPlay: _wrongShakePlay,
        duration: _wrongShakeDuration,
        shakeConstant: ShakeHorizontalConstant2(),
        child: FloatingActionButton(
          onPressed: _newQuestion,
          tooltip: 'New question',
          child: const Icon(Icons.done),
        ),
      ),
    );
  }
}
