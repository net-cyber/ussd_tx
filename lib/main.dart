import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:ussd_advanced/ussd_advanced.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sim_data/sim_data.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'USSD Manager',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late TextEditingController _controller;
  String? _response;
  bool _permissionsGranted = false;
  SimData? _simData;
  List<SimCard> _simCards = [];
  TextEditingController _phoneUssdController = TextEditingController(text: "*111#");
  int? _defaultDataSimIndex;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _checkPermissions();
    _getSimCardInfo();
  }
  
  // Load SIM card information
  Future<void> _getSimCardInfo() async {
    try {
      _simData = await SimDataPlugin.getSimData();
      setState(() {
        if (_simData != null && _simData!.cards.isNotEmpty) {
          _simCards = _simData!.cards;
          _response = "Detected ${_simCards.length} SIM card(s)";
          _detectDefaultDataSim();
        } else {
          _response = "No SIM cards detected";
        }
      });
    } on PlatformException catch (e) {
      setState(() {
        _response = "Error detecting SIM cards: ${e.message}";
      });
    }
  }
  
  // Detect which SIM is used for internet data
  void _detectDefaultDataSim() {
    try {
      if (_simCards.isEmpty) return;
      
      // In Android, the default data SIM is usually marked as isDataRoaming: false
      // and often has a specific subscriptionId
      for (int i = 0; i < _simCards.length; i++) {
        final sim = _simCards[i];
        // Default data SIM usually has the lowest subscription ID or is marked in some way
        if (sim.isDataRoaming != null && sim.isDataRoaming == false) {
          _defaultDataSimIndex = i;
          break;
        }
      }
      
      // If still null, just use the first SIM as default
      _defaultDataSimIndex ??= 0;
    } catch (e) {
      debugPrint("Error detecting default data SIM: $e");
    }
  }
  
  // Show dialog to select SIM card
  Future<int?> _selectSimCard(BuildContext context) async {
    if (_simCards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No SIM cards detected')),
      );
      return null;
    }
    
    if (_simCards.length == 1) {
      return 1; // Only one SIM, use subscriptionId 1
    }
    
    // For multiple SIMs, show selection dialog
    return showDialog<int>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select SIM Card'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_simCards.length, (index) {
              final sim = _simCards[index];
              return ListTile(
                title: Text('SIM ${index + 1}${sim.displayName.isNotEmpty ? ": ${sim.displayName}" : ""}'),
                subtitle: Text(sim.carrierName.isNotEmpty ? sim.carrierName : 'Unknown carrier'),
                onTap: () {
                  Navigator.of(context).pop(index + 1); // Return 1-based index (subscriptionId)
                },
              );
            }),
          ),
        );
      },
    );
  }

  // Updated method to check and request permissions
  Future<void> _checkPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.phone,
    ].request();
    
    bool allGranted = true;
    String deniedPermissions = '';
    
    statuses.forEach((permission, status) {
      if (!status.isGranted) {
        allGranted = false;
        deniedPermissions += '${permission.toString()}, ';
      }
    });
    
    setState(() {
      _permissionsGranted = allGranted;
      if (!allGranted) {
        _response = "Missing permissions: ${deniedPermissions.isEmpty ? "None" : deniedPermissions.substring(0, deniedPermissions.length - 2)}. "
            "Please grant permissions in Settings to use USSD features";
      }
    });

    // If permissions are denied, show dialog to open settings
    if (!allGranted) {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Permissions Required'),
            content: const Text('This app needs phone permissions to function properly. '
                'Please grant the required permissions in Settings.'),
            actions: [
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.of(context).pop(),
              ),
              TextButton(
                child: const Text('Open Settings'),
                onPressed: () {
                  Navigator.of(context).pop();
                  openAppSettings();
                },
              ),
            ],
          ),
        );
      }
    }
  }

  // Updated USSD operation method with SIM selection
  Future<void> _performUssdOperation({
    required String code,
    int? simCard,
    required Future<String?> Function(int) operation
  }) async {
    if (!_permissionsGranted) {
      await _checkPermissions();
      if (!_permissionsGranted) {
        setState(() {
          _response = "Cannot perform USSD operation: Missing permissions";
        });
        return;
      }
    }
    
    // If no simCard is provided, ask user to select
    final selectedSim = simCard ?? await _selectSimCard(context);
    if (selectedSim == null) {
      setState(() {
        _response = "No SIM card selected";
      });
      return;
    }
    
    setState(() {
      _response = "Sending USSD code to SIM$selectedSim...";
    });
    
    try {
      // Use direct subscriptionId for the plugin
      // SIM1 = 1, SIM2 = 2
      debugPrint("Using direct subscriptionId: $selectedSim for SIM$selectedSim");
      
      // Pass the direct subscription ID
      String? res = await operation(selectedSim);
      setState(() {
        _response = res != null 
            ? "SIM$selectedSim Response: $res" 
            : "No response received from SIM$selectedSim";
      });
    } catch (e) {
      setState(() {
        _response = "Error with SIM$selectedSim: ${e.toString()}";
      });
      debugPrint("USSD Error for SIM$selectedSim: ${e.toString()}");
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _phoneUssdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('USSD Manager'),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          // text input
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _controller,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'USSD code'),
            ),
          ),

          // display response if any
          if (_response != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_response!),
              ),
            ),

          // buttons
          Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: !_permissionsGranted 
                  ? () => _checkPermissions() 
                  : () async {
                      final simId = await _selectSimCard(context);
                      if (simId != null) {
                        // Use direct subscriptionId for the plugin
                        // SIM1 = 1, SIM2 = 2
                        debugPrint("Using direct subscriptionId: $simId for SIM$simId");
                        
                        UssdAdvanced.sendUssd(
                          code: _controller.text, 
                          subscriptionId: simId
                        );
                      }
                    },
                child: const Text('normal\nrequest'),
              ),
              ElevatedButton(
                onPressed: () async {
                  _performUssdOperation(
                    code: _controller.text,
                    operation: (simId) => UssdAdvanced.sendAdvancedUssd(
                      code: _controller.text, 
                      subscriptionId: simId
                    ),
                  );
                },
                child: const Text('single session\nrequest'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final simId = await _selectSimCard(context);
                  if (simId == null) return;
                  
                  if (!_permissionsGranted) {
                    await _checkPermissions();
                    if (!_permissionsGranted) return;
                  }
                  
                  try {
                    // Convert to 0-based index for the plugin
                    final adjustedSimId = simId - 1;
                    debugPrint("Using subscriptionId: $adjustedSimId for SIM$simId");
                    
                    String? _res = await UssdAdvanced.multisessionUssd(
                      code: _controller.text, 
                      subscriptionId: adjustedSimId
                    );
                    setState(() {
                      _response = "SIM$simId Response: $_res";
                    });
                    String? _res2 = await UssdAdvanced.sendMessage('0');
                    setState(() {
                      _response = "SIM$simId Response: $_res2";
                    });
                    await UssdAdvanced.cancelSession();
                  } catch (e) {
                    setState(() {
                      _response = "Error with SIM$simId: ${e.toString()}";
                    });
                    debugPrint("Multi-session Error for SIM$simId: ${e.toString()}");
                  }
                },
                child: const Text('multi session\nrequest'),
              ),
            ],
          ),
          
          // Display SIM info if available
          if (_simCards.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Column(
                children: [
                  const Text('Available SIM Cards:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...List.generate(_simCards.length, (index) {
                    final sim = _simCards[index];
                    bool isDefaultDataSim = _defaultDataSimIndex == index;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'SIM ${index + 1}: ${sim.carrierName} (${sim.serialNumber})',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isDefaultDataSim ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          if (isDefaultDataSim)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(Icons.wifi, color: Colors.blue, size: 14),
                            ),
                        ],
                      ),
                    );
                  }),
                  if (_defaultDataSimIndex != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Internet Data is using SIM ${_defaultDataSimIndex! + 1}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          
          // Add Buttons for specific USSD codes
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                const Text('USSD Shortcuts', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        final simId = await _selectSimCard(context);
                        if (simId == null) return;
                        
                        setState(() {
                          _response = "Checking phone number on SIM$simId...";
                        });
                        
                        try {
                          // IMPORTANT: For Android's ussd_advanced plugin, use direct SIM ID without adjustment
                          // SIM1 = 1, SIM2 = 2
                          debugPrint("Using direct subscriptionId: $simId for SIM$simId");
                          
                          String? res = await UssdAdvanced.sendAdvancedUssd(
                            code: "*111#", 
                            subscriptionId: simId
                          );
                          
                          setState(() {
                            _response = res != null 
                                ? "SIM$simId Phone Number: $res" 
                                : "Failed to retrieve phone number from SIM$simId";
                          });
                        } catch (e) {
                          setState(() {
                            _response = "Error checking SIM$simId: ${e.toString()}";
                          });
                          debugPrint("Error checking phone number for SIM$simId: ${e.toString()}");
                        }
                      },
                      child: const Text('Check Phone\nNumber'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final simId = await _selectSimCard(context);
                        if (simId == null) return;
                        
                        setState(() {
                          _response = "Checking data balance on SIM$simId...";
                        });
                        
                        try {
                          // Use direct subscriptionId for the plugin
                          // SIM1 = 1, SIM2 = 2
                          debugPrint("Using direct subscriptionId: $simId for SIM$simId");
                          
                          String? res = await UssdAdvanced.sendAdvancedUssd(
                            code: "*121#", 
                            subscriptionId: simId
                          );
                          setState(() {
                            _response = res != null 
                                ? "SIM$simId Data Balance: $res" 
                                : "Failed to retrieve data balance from SIM$simId";
                          });
                        } catch (e) {
                          setState(() {
                            _response = "Error checking SIM$simId: ${e.toString()}";
                          });
                          debugPrint("Error checking data balance for SIM$simId: ${e.toString()}");
                        }
                      },
                      child: const Text('Check Data\nBalance'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Custom USSD code section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Custom USSD Code',
                    hintText: 'Enter any USSD code',
                  ),
                  controller: _phoneUssdController,
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () async {
                    final ussdCode = _phoneUssdController.text;
                    if (ussdCode.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a USSD code')),
                      );
                      return;
                    }
                    
                    final simId = await _selectSimCard(context);
                    if (simId == null) return;
                    
                    setState(() {
                      _response = "Sending code $ussdCode to SIM$simId...";
                    });
                    
                    try {
                      // Use direct subscriptionId for the plugin
                      // SIM1 = 1, SIM2 = 2
                      debugPrint("Using direct subscriptionId: $simId for SIM$simId");
                      
                      String? res = await UssdAdvanced.sendAdvancedUssd(
                        code: ussdCode, 
                        subscriptionId: simId
                      );
                      setState(() {
                        _response = res != null 
                            ? "SIM$simId Response: $res" 
                            : "No response received from SIM$simId";
                      });
                    } catch (e) {
                      setState(() {
                        _response = "Error with SIM$simId: ${e.toString()}";
                      });
                      debugPrint("USSD Error for SIM$simId: ${e.toString()}");
                    }
                  },
                  child: const Text('Send USSD Code'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}