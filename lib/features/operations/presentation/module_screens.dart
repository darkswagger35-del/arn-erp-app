import 'package:flutter/material.dart';

import 'entity_list_screen.dart';

class ProductsScreen extends StatelessWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EntityListScreen(
      title: 'Ürünler',
      table: 'products',
      primaryLabelKey: 'name',
      subtitleKeys: ['sku', 'category', 'stock_quantity', 'sale_price'],
      fields: [
        EntityField(keyName: 'name', label: 'Ürün adı', required: true),
        EntityField(keyName: 'sku', label: 'Ürün kodu'),
        EntityField(keyName: 'barcode', label: 'Barkod'),
        EntityField(keyName: 'category', label: 'Kategori'),
        EntityField(keyName: 'unit', label: 'Birim'),
        EntityField(
          keyName: 'purchase_price',
          label: 'Alış fiyatı (₺)',
          numeric: true,
          keyboardType: TextInputType.number,
        ),
        EntityField(
          keyName: 'sale_price',
          label: 'Satış fiyatı (₺)',
          numeric: true,
          keyboardType: TextInputType.number,
        ),
        EntityField(
          keyName: 'stock_quantity',
          label: 'Stok miktarı',
          numeric: true,
          keyboardType: TextInputType.number,
        ),
        EntityField(
          keyName: 'critical_stock',
          label: 'Kritik stok',
          numeric: true,
          keyboardType: TextInputType.number,
        ),
      ],
    );
  }
}

class VehiclesScreen extends StatelessWidget {
  const VehiclesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EntityListScreen(
      title: 'Araçlar',
      table: 'vehicles',
      primaryLabelKey: 'plate',
      subtitleKeys: ['brand', 'model', 'current_km'],
      fields: [
        EntityField(keyName: 'plate', label: 'Plaka', required: true),
        EntityField(keyName: 'brand', label: 'Marka'),
        EntityField(keyName: 'model', label: 'Model'),
        EntityField(
          keyName: 'model_year',
          label: 'Model yılı',
          numeric: true,
          keyboardType: TextInputType.number,
        ),
        EntityField(
          keyName: 'current_km',
          label: 'Kilometre',
          numeric: true,
          keyboardType: TextInputType.number,
        ),
        EntityField(keyName: 'notes', label: 'Notlar'),
      ],
    );
  }
}

class WarehousesScreen extends StatelessWidget {
  const WarehousesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EntityListScreen(
      title: 'Depolar',
      table: 'warehouses',
      primaryLabelKey: 'name',
      subtitleKeys: ['type', 'address'],
      fields: [
        EntityField(keyName: 'name', label: 'Depo adı', required: true),
        EntityField(keyName: 'type', label: 'Tür (main/vehicle/branch)'),
        EntityField(keyName: 'address', label: 'Adres'),
        EntityField(keyName: 'notes', label: 'Notlar'),
      ],
    );
  }
}

class PaymentsScreen extends StatelessWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EntityListScreen(
      title: 'Tahsilatlar',
      table: 'payments',
      primaryLabelKey: 'description',
      subtitleKeys: ['amount', 'payment_method', 'payment_date'],
      fields: [
        EntityField(keyName: 'description', label: 'Açıklama', required: true),
        EntityField(
          keyName: 'amount',
          label: 'Tutar (₺)',
          required: true,
          numeric: true,
          keyboardType: TextInputType.number,
        ),
        EntityField(keyName: 'payment_method', label: 'Ödeme yöntemi'),
        EntityField(keyName: 'payment_date', label: 'Tarih (2026-07-26)'),
        EntityField(keyName: 'customer_id', label: 'Müşteri ID'),
        EntityField(keyName: 'service_request_id', label: 'Servis Talebi ID'),
      ],
    );
  }
}

class StockMovementsScreen extends StatelessWidget {
  const StockMovementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EntityListScreen(
      title: 'Stok Hareketleri',
      table: 'stock_movements',
      primaryLabelKey: 'movement_type',
      subtitleKeys: ['product_id', 'quantity', 'notes'],
      fields: [
        EntityField(keyName: 'product_id', label: 'Ürün ID', required: true),
        EntityField(keyName: 'warehouse_id', label: 'Depo ID'),
        EntityField(
          keyName: 'movement_type',
          label: 'Tür (in/out/transfer)',
          required: true,
        ),
        EntityField(
          keyName: 'quantity',
          label: 'Miktar',
          required: true,
          numeric: true,
          keyboardType: TextInputType.number,
        ),
        EntityField(keyName: 'notes', label: 'Notlar'),
      ],
    );
  }
}
