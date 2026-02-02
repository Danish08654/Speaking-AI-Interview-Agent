import 'dart:async';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class InterviewTestScreen extends StatefulWidget {
  const InterviewTestScreen({super.key});

  @override
  State<InterviewTestScreen> createState() => _InterviewTestScreenState();
}

class _InterviewTestScreenState extends State<InterviewTestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _aboutController = TextEditingController();
  final _reasonController = TextEditingController();
  final _strengthController = TextEditingController();

  final FlutterTts _flutterTts = FlutterTts();
  late stt.SpeechToText _speech;

  int _currentQuestion = 0;
  int _timerSeconds = 30;
  Timer? _timer;

  bool _ttsSpeaking = false;
  bool _isListening = false;

  final List<Map<String, dynamic>> _questions = [];
  final List<bool> _fieldLocked = [false, false, false];

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();

    _questions.addAll([
      {
        'label': "Tell me about yourself",
        'controller': _aboutController,
        'validation': "Please enter something about yourself"
      },
      {
        'label': "Why do you want this job?",
        'controller': _reasonController,
        'validation': "Please explain your reason"
      },
      {
        'label': "What are your strengths?",
        'controller': _strengthController,
        'validation': "Please share your strengths"
      },
    ]);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _showTipsDialog();
      _startTimer();
    });

    _flutterTts.setCompletionHandler(() => setState(() => _ttsSpeaking = false));
    _flutterTts.setErrorHandler((msg) => setState(() => _ttsSpeaking = false));
  }

  @override
  void dispose() {
    _aboutController.dispose();
    _reasonController.dispose();
    _strengthController.dispose();
    _flutterTts.stop();
    _speech.stop();
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _timerSeconds = 30);

    _speak(_questions[_currentQuestion]['label']);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _timerSeconds--);
      if (_timerSeconds <= 0) {
        _fieldLocked[_currentQuestion] = true;
        _stopListening();
        timer.cancel();
        if (_currentQuestion < _questions.length - 1) {
          setState(() => _currentQuestion++);
          _startTimer();
        }
      }
    });
  }

  Future<void> _speak(String text) async {
    if (_ttsSpeaking) await _flutterTts.stop();
    setState(() => _ttsSpeaking = true);
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setPitch(1.0);
    await _flutterTts.speak(text);
  }

  Future<void> _listen(TextEditingController controller) async {
    if (_fieldLocked[_currentQuestion]) return;

    if (_isListening) {
      _speech.stop();
      setState(() => _isListening = false);
      return;
    }

    bool available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done') {
          setState(() => _isListening = false);
        }
      },
      onError: (error) => debugPrint("Speech error: $error"),
    );

    if (!available) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition not available')),
      );
      return;
    }

    setState(() => _isListening = true);

    _speech.listen(
      localeId: 'en_US',
      onResult: (result) {
        if (result.finalResult) {
          controller.text +=
              (controller.text.isEmpty ? '' : ' ') + result.recognizedWords;
        }
      },
    );
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _isListening = false);
  }

  bool _validateAnswers() {
    final about = _aboutController.text.toLowerCase();
    final reason = _reasonController.text.toLowerCase();
    final strength = _strengthController.text.toLowerCase();

    return (about.contains('name') || about.contains('study')) &&
        (reason.contains('passion') || reason.contains('learn')) &&
        (strength.contains('hardworking') || strength.contains('team'));
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final passed = _validateAnswers();

      final data = {
        'interviewTest': {
          'about': _aboutController.text.trim(),
          'reason': _reasonController.text.trim(),
          'strength': _strengthController.text.trim(),
          'status': passed ? 'Passed' : 'Failed',
          'timestamp': FieldValue.serverTimestamp(),
        },
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(data, SetOptions(merge: true));

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(passed ? 'Interview Passed!' : 'Interview Failed'),
          content: Text(passed
              ? 'Your answers were accepted.\nProceed to the medical test.'
              : 'Your answers didn’t meet the required keywords.\nPlease talk more about your personality, goals, and strengths.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (passed) {
                  Navigator.pushReplacementNamed(context, '/medical-test');
                }
              },
              child: Text(passed ? 'Continue' : 'Try Again'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _showTipsDialog() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Interview Tips'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("• Mention your name, education, and background."),
            Text("• Explain your passion and eagerness to learn."),
            Text("• Use words like: hardworking, team player, problem solver."),
            SizedBox(height: 12),
            Text(
              " You have 30 seconds for each question. Once time runs out, the answer box will be locked.",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(int index) {
    final item = _questions[index];
    final isLocked = _fieldLocked[index];
    final isCurrent = index == _currentQuestion;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item['label'],
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            if (isCurrent)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("⏱ Time Left: $_timerSeconds sec", style: const TextStyle(fontSize: 14)),
                  IconButton(
                    icon: const Icon(Icons.mic, color: Colors.deepPurple),
                    tooltip: 'Speak your answer',
                    onPressed: () => _listen(item['controller']),
                  ),
                ],
              ),
            GestureDetector(
              onTap: () => _speak(item['label']),
              child: TextFormField(
                controller: item['controller'],
                maxLines: null,
                minLines: 3,
                enabled: !isLocked,
                validator: (value) =>
                value == null || value.isEmpty ? item['validation'] : null,
                decoration: InputDecoration(
                  hintText: isLocked ? "Time expired" : "Tap mic or type your answer...",
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Interview Test'),
        backgroundColor: Colors.deepPurple,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: "Interview Tips",
            onPressed: _showTipsDialog,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              ...List.generate(_questions.length, (i) => _buildQuestionCard(i)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _submitForm,
                icon: const Icon(Icons.send),
                label: const Text("Submit Interview"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
