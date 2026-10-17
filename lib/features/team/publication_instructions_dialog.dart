import 'package:flutter/material.dart';
class PublicationInstructionsDialog extends StatefulWidget {
 const PublicationInstructionsDialog({super.key, required this.initialInstructions});
 final String initialInstructions;
 @override
 State<PublicationInstructionsDialog> createState() => _PublicationInstructionsDialogState();
}
class _PublicationInstructionsDialogState extends State<PublicationInstructionsDialog> {
 late final TextEditingController _controller = TextEditingController(text: widget.initialInstructions);
 @override
 void dispose() { _controller.dispose(); super.dispose(); }
 @override
 Widget build(BuildContext context) => AlertDialog(
 title: const Text('Special instructions'),
 content: SizedBox(width:560, child: SingleChildScrollView(child: Column(mainAxisSize:MainAxisSize.min,children:[
 const Text('Any instructions for the team? These will be included in the team-sheet email and match reminder. Leave blank if none are needed.'),
 const SizedBox(height:12),
 TextField(controller:_controller,minLines:3,maxLines:8,maxLength:5000,
 decoration:const InputDecoration(labelText:'Special instructions',hintText:'Arrival time, dress code or travel arrangements',border:OutlineInputBorder())),
 ]))),
 actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),
 FilledButton(onPressed:()=>Navigator.pop(context,_controller.text.trim()),child:const Text('Continue to publish'))]);
}
