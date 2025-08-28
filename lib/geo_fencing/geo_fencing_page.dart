import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
// import 'package:luckygo_admin/geo_fencing/create_geofencing.dart';
import 'package:luckygo_admin/geo_fencing/set_map_viewport.dart';
import 'package:luckygo_admin/geo_fencing/view_saved_map.dart';
import 'package:luckygo_admin/global.dart';

class GeoFencingPage extends StatelessWidget {
  const GeoFencingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Geo Fencing'),
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SetMapViewport()),
                  );
                },
                child: const Text('Google Maps'),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Fill remaining space with the list
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection(negara)
                  .doc(negeri)
                  .collection('information')
                  .doc('geo_fencing')
                  .collection('geo_fencing_button')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('No data found'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final docSnap = docs[i];
                    final docId = docSnap.id;
                    final data = docSnap.data();
                    final nameForUi = (data['name'] ?? docId).toString();

                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ViewSavedMap(
                              center: data['center'],
                              zoom: data['zoom'],
                              bearing: data['bearing'],
                              tilt: data['tilt'],
                              myloc: data['myloc'],
                              name: nameForUi,
                            ),
                          ),
                        );
                      },
                      child: Dismissible(
                        key: ValueKey(docId),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (direction) async {
                          return await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Delete this entry?'),
                              content: Text('This will remove “$nameForUi”.'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                        },
                        onDismissed: (_) async {
                          await FirebaseFirestore.instance
                              .collection(negara)
                              .doc(negeri)
                              .collection('information')
                              .doc('geo_fencing')
                              .collection('geo_fencing_button')
                              .doc(docId)
                              .delete();

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Deleted $nameForUi')),
                          );
                        },
                        child: Card(
                          child: ListTile(
                            leading: const Icon(Icons.place_outlined),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    nameForUi,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  tooltip: 'Delete',
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title:
                                            const Text('Delete this entry?'),
                                        content: Text(
                                            'This will remove “$nameForUi”.'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('Cancel'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.red),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      await FirebaseFirestore.instance
                                          .collection(negara)
                                          .doc(negeri)
                                          .collection('information')
                                          .doc('geo_fencing')
                                          .collection('geo_fencing_button')
                                          .doc(docId)
                                          .delete();
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                                content: Text(
                                                    'Deleted $nameForUi')));
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Text('Center: ${data['center'] ?? ''}'),
                                  // Text('My Location: ${data['myloc'] ?? ''}'),
                                  // Text('Bearing: ${data['bearing'] ?? ''}'),
                                  // Text('Tilt: ${data['tilt'] ?? ''}'),
                                  // Text('Zoom: ${data['zoom'] ?? ''}'),
                                ],
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
