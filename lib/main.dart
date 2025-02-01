import 'package:flutter/material.dart';
import 'package:sim_data/sim_data.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('SIM Card Info')),
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              SimData simData = await SimDataPlugin.getSimData();
              print('Carrier Name: ${simData.cards[0].carrierName}');
              print('Country Code: ${simData.cards[0].countryCode}');
              print('SIM Serial: ${simData.cards[0].serialNumber}');
              print('SIM mcc: ${simData.cards[0].mcc}');
              print('SIM mnc: ${simData.cards[0].mnc}');
              print('SIM service provider: ${simData.cards[0].carrierName}');
              print('SIM service subscription: ${simData.cards[0].subscriptionId}');
              print('SIM service subscription: ${simData.cards[0].serialNumber}');
            },
            child: const Text('Get SIM Card Info'),
          ),
        ),
      ),
    );
  }
}