// ==================== Inpaint Page ==================== //

// Flutter imports
import 'package:flutter/material.dart';

// Local imports - Elements
import 'package:sd_companion/elements/ui/image_upload_container.dart';
import 'package:sd_companion/elements/widgets/glass_app_bar.dart';

// Inpaint Page Implementation

class InpaintPage extends StatefulWidget {
  const InpaintPage({super.key});

  @override
  InpaintPageState createState() => InpaintPageState();
}

class InpaintPageState extends State<InpaintPage>
    with AutomaticKeepAliveClientMixin {
  // ===== Build Methods ===== //

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: const Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        extendBodyBehindAppBar: true,
        appBar: GlassAppBar(title: 'CANVAS'),
        body: SingleChildScrollView(
          physics: BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, 110, 16, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Focus(autofocus: true, child: SizedBox.shrink()),
              ImageContainer(),
            ],
          ),
        ),
      ),
    );
  }
}
