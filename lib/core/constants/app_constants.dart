// App-wide constants
class AppConstants {
  AppConstants._();

  // App info
  static const appName = '101 RepairShop';
  static const appVersion = '1.0.0';

  // Appointment time slots
  static const timeSlots = [
    '8:00 AM - 9:00 AM',
    '9:00 AM - 10:00 AM',
    '10:00 AM - 11:00 AM',
    '11:00 AM - 12:00 PM',
    '1:00 PM - 2:00 PM',
    '2:00 PM - 3:00 PM',
    '3:00 PM - 4:00 PM',
    '4:00 PM - 5:00 PM',
  ];

  // Appliance categories
  static const applianceCategories = [
    'Air Conditioner',
    'Refrigerator',
    'Washing Machine',
    'Microwave',
    'Television',
    'Electric Fan',
    'Water Heater',
    'Oven',
    'Other',
  ];

  // Appliance sizes (must match `appliances.appliance_size` in the web admin)
  static const applianceSizes = ['Small', 'Medium', 'Large'];
}
