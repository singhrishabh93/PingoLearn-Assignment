import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool maskEmail = true;
  List<Comment> _comments = [];
  List<Comment> _filteredComments = [];
  int _page = 1;
  final int _limit = 10;
  bool _isLoading = false;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Comment? _pinnedComment;

  @override
  void initState() {
    super.initState();
    fetchRemoteConfig();
    _fetchComments();
    _loadPinnedComment();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels ==
              _scrollController.position.maxScrollExtent &&
          _hasMore) {
        _fetchComments();
      }
    });
    _searchController.addListener(_searchComments);
  }

  Future<void> fetchRemoteConfig() async {
    final FirebaseRemoteConfig remoteConfig = FirebaseRemoteConfig.instance;

    try {
      await remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: Duration(seconds: 10),
        minimumFetchInterval: Duration(hours: 1),
      ));
      await remoteConfig.fetchAndActivate();
      setState(() {
        maskEmail = remoteConfig.getBool('mask_email');
      });
    } catch (e) {
      print("Remote Config fetch failed: $e");
    }
  }

  Future<void> _fetchComments() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });
    final response = await http.get(Uri.parse(
        'https://jsonplaceholder.typicode.com/comments?_page=$_page&_limit=$_limit'));

    if (response.statusCode == 200) {
      List jsonResponse = json.decode(response.body);
      List<Comment> newComments =
          jsonResponse.map((comment) => Comment.fromJson(comment)).toList();

      setState(() {
        _comments.addAll(newComments);
        _filteredComments = _comments;
        _isLoading = false;
        _hasMore = newComments.length == _limit;
        _page++;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
      throw Exception('Failed to load comments');
    }
  }

  Future<void> _refreshComments() async {
    setState(() {
      _comments.clear();
      _page = 1;
      _hasMore = true;
    });
    await _fetchComments();
  }

  void _searchComments() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredComments = _comments.where((comment) {
        return comment.name.toLowerCase().contains(query) ||
            comment.email.toLowerCase().contains(query) ||
            comment.body.toLowerCase().contains(query);
      }).toList();
    });
  }

  Future<void> _loadPinnedComment() async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedCommentJson = prefs.getString('pinned_comment');
    if (pinnedCommentJson != null) {
      setState(() {
        _pinnedComment = Comment.fromJson(json.decode(pinnedCommentJson));
      });
    }
  }

  Future<void> _pinComment(Comment comment) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pinned_comment', json.encode(comment.toJson()));
    setState(() {
      _pinnedComment = comment;
    });
  }

  Future<void> _unpinComment() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pinned_comment');
    setState(() {
      _pinnedComment = null;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 80,
        title: const Text("Comments",
            style: TextStyle(color: Color(0xffF5F9FD), fontFamily: 'Bold')),
        automaticallyImplyLeading: false,
        backgroundColor: Color(0xff0C54BE),
        actions: [
          Switch(
            value: !maskEmail,
            onChanged: (value) {
              setState(() {
                maskEmail = !value;
              });
            },
            activeColor: Colors.white,
          ),
          if (_pinnedComment != null)
            IconButton(
              icon: Icon(Icons.push_pin, color: Colors.white),
              onPressed: _unpinComment,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(50.0),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              style: TextStyle(color: Colors.white, fontFamily: 'Medium'),
              controller: _searchController,
              cursorColor: Colors.white,
              decoration: InputDecoration(
                hintText: 'Search comments...',
                hintStyle: TextStyle(color: Colors.white, fontFamily: 'Medium'),
                prefixIcon: Icon(Icons.search, color: Colors.white),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                  borderRadius: BorderRadius.circular(25.0),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25.0),
                  borderSide: BorderSide(
                    color: Colors.white,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25.0),
                  borderSide: BorderSide(
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: Color(0xff0C54BE),
        onRefresh: _refreshComments,
        child: _isLoading && _comments.isEmpty
            ? Center(
                child: CircularProgressIndicator(
                  color: Color(0xff0C54BE),
                ),
              )
            : ListView.builder(
                controller: _scrollController,
                itemCount: _filteredComments.length +
                    (_isLoading ? 1 : 0) +
                    (_pinnedComment != null ? 1 : 0),
                itemBuilder: (context, index) {
                  if (_pinnedComment != null && index == 0) {
                    return CommentCard(
                        comment: _pinnedComment!, maskEmail: maskEmail);
                  }
                  if (index == _filteredComments.length +
                      (_pinnedComment != null ? 1 : 0)) {
                    return Center(
                        child: CircularProgressIndicator(
                      color: Color(0xff0C54BE),
                    ));
                  }
                  return GestureDetector(
                    onLongPress: () {
                      _showCommentOptions(context, _filteredComments[
                          _pinnedComment != null ? index - 1 : index]);
                    },
                    child: CommentCard(
                        comment: _filteredComments[
                            _pinnedComment != null ? index - 1 : index],
                        maskEmail: maskEmail),
                  );
                },
              ),
      ),
    );
  }

  void _showCommentOptions(BuildContext context, Comment comment) {
    showModalBottomSheet(
      backgroundColor: Color(0xff0C54BE),
      context: context,
      builder: (context) => Wrap(
        children: [
          ListTile(
            leading: Icon(Icons.push_pin, color: Colors.white),
            title: Text('Pin to Top', style: TextStyle(fontFamily: 'Medium', color: Colors.white),),
            onTap: () {
              Navigator.pop(context);
              _pinComment(comment);
            },
          ),
          ListTile(
            leading: Icon(Icons.emoji_emotions, color: Colors.white),
            title: Text('React', style: TextStyle(fontFamily: 'Medium', color: Colors.white),),
            onTap: () {
              Navigator.pop(context);
              _showReactionOptions(context, comment);
            },
          ),
        ],
      ),
    );
  }

  void _showReactionOptions(BuildContext context, Comment comment) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xff0C54BE),
        title: Text('React to Comment', style: TextStyle(fontFamily: 'Medium', color: Colors.white),),
        content: Wrap(
          spacing: 10,
          children: ['👍','😀', '😢', '😡', '❤️', '👎'].map((emoji) {
            return GestureDetector(
              onTap: () {
                setState(() {
                  comment.reaction = emoji;
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('You reacted with $emoji', style: TextStyle(fontFamily: 'Medium') ),
                  ),
                );
              },
              child: Text(
                emoji,
                style: TextStyle(fontSize: 30),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class Comment {
  final int postId;
  final int id;
  final String name;
  final String email;
  final String body;
  String? reaction;

  Comment(
      {required this.postId,
      required this.id,
      required this.name,
      required this.email,
      required this.body,
      this.reaction});

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      postId: json['postId'],
      id: json['id'],
      name: json['name'],
      email: json['email'],
      body: json['body'],
      reaction: json['reaction'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'postId': postId,
      'id': id,
      'name': name,
      'email': email,
      'body': body,
      'reaction': reaction,
    };
  }
}

class CommentCard extends StatelessWidget {
  final Comment comment;
  final bool maskEmail;

  CommentCard({required this.comment, required this.maskEmail});

  @override
  Widget build(BuildContext context) {
    String email = comment.email;
    if (maskEmail) {
      var parts = email.split('@');
      if (parts[0].length > 3) {
        email = parts[0].substring(0, 3) +
            '*' * (parts[0].length - 3) +
            '@' +
            parts[1];
      }
    }

    return Card(
      color: Colors.white,
      margin: EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: Color(0xffCED3DC),
              child: Center(
                child: Text(
                  comment.name[0],
                  style: TextStyle(
                      color: Color(0xff303F60),
                      fontSize: 30,
                      fontFamily: 'Bold'),
                ),
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Name:  ',
                        style: TextStyle(
                            color: Colors.grey,
                            fontFamily: 'Medium',
                            fontSize: 16,
                            fontStyle: FontStyle.italic),
                      ),
                      Expanded(
                        child: Text(
                          comment.name,
                          style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Bold',
                              fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        'Email:  ',
                        style: TextStyle(
                            color: Colors.grey,
                            fontFamily: 'Medium',
                            fontSize: 16,
                            fontStyle: FontStyle.italic),
                      ),
                      Expanded(
                        child: Text(
                          email,
                          style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Bold',
                              fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Text(
                    comment.body,
                    style: TextStyle(
                      fontFamily: 'Medium',
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 4,
                  ),
                  if (comment.reaction != null)
                    Text(
                      'Reaction: ${comment.reaction}',
                      style: TextStyle(
                          fontFamily: 'Medium',
                          fontSize: 16,
                          fontStyle: FontStyle.italic),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
