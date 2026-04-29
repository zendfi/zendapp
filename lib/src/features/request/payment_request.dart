import 'package:flutter/material.dart';

enum PaymentRequestStatus { pending, paid, expired }

class RequestCustomisation {
  const RequestCustomisation({
    this.personalNote = '',
    this.themeColor,
  });

  final String personalNote;
  final Color? themeColor;
}

class PaymentRequest {
  PaymentRequest({
    required this.id,
    required this.link,
    required this.amount,
    required this.description,
    required this.createdAt,
    this.expiryDate,
    this.customisation,
    this.status = PaymentRequestStatus.pending,
  });

  final String id;
  final String link;
  final double amount;
  final String description;
  final DateTime createdAt;
  final DateTime? expiryDate;
  final RequestCustomisation? customisation;
  final PaymentRequestStatus status;
}
