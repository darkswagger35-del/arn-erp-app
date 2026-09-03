import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/app_role.dart';
import '../core/auth/auth_provider.dart';
import '../core/auth/auth_state.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/customers/presentation/screens/customer_detail_screen.dart';
import '../features/customers/presentation/screens/customer_form_screen.dart';
import '../features/customers/presentation/screens/customer_list_screen.dart';
import '../features/dashboard/presentation/admin_dashboard_screen.dart';
import '../features/dashboard/presentation/secretary_dashboard_screen.dart';
import '../features/secretary_crm/presentation/secretary_follow_up_screen.dart';
import '../features/secretary_crm/presentation/secretary_performance_screen.dart';
import '../features/dashboard/presentation/technician_dashboard_screen.dart';
import '../features/service_requests/presentation/screens/service_request_form_screen.dart';
import '../features/service_requests/presentation/screens/service_request_list_screen.dart';
import '../features/service_requests/data/models/service_request_model.dart';
import '../features/service_execution/presentation/service_execution_screen.dart';
import '../features/service_execution/presentation/technician_jobs_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/operations/presentation/module_screens.dart'
    hide ProductsScreen, WarehousesScreen, StockMovementsScreen;
import '../features/products/presentation/product_management_screen.dart';
import '../features/operations/presentation/reports_screen.dart';
import '../features/user_management/presentation/user_management_screen.dart';
import '../features/inventory/presentation/warehouse_management_screen.dart';
import '../features/inventory/presentation/stock_movements_screen.dart';
import '../features/finance/presentation/payments_screen.dart';
import '../features/cash_register/presentation/cash_register_screen.dart';
import '../features/notifications/presentation/notification_center_screen.dart';
import '../features/service_planning/presentation/service_planning_screen.dart';
import '../features/documents/presentation/service_documents_screen.dart';
import '../features/documents/presentation/service_form_designer_screen.dart';
import '../features/dispatch/presentation/dispatch_board_screen.dart';
import '../features/customer_portal/presentation/customer_portal_screen.dart';
import '../features/maintenance/presentation/historical_customer_screen.dart';
import '../features/maintenance/presentation/upcoming_maintenance_screen.dart';
import '../features/data_transfer/presentation/excel_transfer_screen.dart';
import '../features/location_tracking/presentation/technician_locations_screen.dart';


final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'rootNavigator');

String backFallbackRoute(String currentPath, AppRole? role) {
  final normalized = currentPath.split('?').first;

  final technicianJob = RegExp(r'^/technician/jobs/[^/]+$');
  if (technicianJob.hasMatch(normalized)) return '/technician/jobs';

  final customerEdit = RegExp(r'^/(manager|secretary|technician)/customers/([^/]+)/edit$').firstMatch(normalized);
  if (customerEdit != null) {
    return '/${customerEdit.group(1)}/customers/${customerEdit.group(2)}';
  }

  final customerDetail = RegExp(r'^/(manager|secretary|technician)/customers/[^/]+$').firstMatch(normalized);
  if (customerDetail != null) return '/${customerDetail.group(1)}/customers';

  final newService = RegExp(r'^/(manager|secretary)/service-requests/new/([^/]+)$').firstMatch(normalized);
  if (newService != null) {
    return '/${newService.group(1)}/customers/${newService.group(2)}';
  }

  if (normalized == '/manager/customers/new') return '/manager/customers';
  if (normalized == '/secretary/customers/new') return '/secretary/customers';
  if (normalized == '/notifications') return _fallbackRouteForRole(role);

  if (normalized.startsWith('/manager/')) return '/admin-dashboard';
  if (normalized.startsWith('/secretary/')) return '/secretary-dashboard';
  if (normalized.startsWith('/technician/')) return '/technician-dashboard';

  return _fallbackRouteForRole(role);
}

String _fallbackRouteForRole(AppRole? currentRole) {
  switch (currentRole) {
    case AppRole.admin:
      return '/admin-dashboard';

    case AppRole.manager:
      return '/admin-dashboard';

    case AppRole.secretary:
      return '/secretary-dashboard';

    case AppRole.technician:
      return '/technician-dashboard';

    default:
      return '/login';
  }
}

bool _matchesRoute(String matchedLocation, String routePrefix) {
  return matchedLocation == routePrefix ||
      matchedLocation.startsWith('$routePrefix/');
}

String? resolveRouteRedirect({
  required String matchedLocation,
  required AppRole? currentRole,
  required bool isAuthenticated,
  required bool isLoginRoute,
}) {
  if (_matchesRoute(matchedLocation, '/portal')) {
    return null;
  }

  if (!isAuthenticated && !isLoginRoute) {
    return '/login';
  }

  if (isAuthenticated && isLoginRoute) {
    return _fallbackRouteForRole(currentRole);
  }

  if (currentRole == null) {
    return null;
  }

  switch (matchedLocation) {
    case '/admin-dashboard':
      if (currentRole != AppRole.admin && currentRole != AppRole.manager) {
        return _fallbackRouteForRole(currentRole);
      }
      break;

    case '/secretary-dashboard':
      if (currentRole != AppRole.secretary &&
          currentRole != AppRole.manager &&
          currentRole != AppRole.admin) {
        return _fallbackRouteForRole(currentRole);
      }
      break;

    case '/technician-dashboard':
      if (currentRole != AppRole.technician &&
          currentRole != AppRole.manager &&
          currentRole != AppRole.admin) {
        return _fallbackRouteForRole(currentRole);
      }
      break;
    case '/technician/cash':
      if (currentRole != AppRole.technician &&
          currentRole != AppRole.manager &&
          currentRole != AppRole.admin) {
        return _fallbackRouteForRole(currentRole);
      }
      break;

    case '/manager/users':
    case '/manager/settings':
    case '/manager/products':
    case '/manager/vehicles':
    case '/manager/warehouses':
    case '/manager/stock-movements':
    case '/manager/payments':
    case '/manager/cash':
    case '/manager/reports':
    case '/manager/service-planning':
    case '/manager/service-documents':
    case '/manager/service-form-designer':
    case '/manager/dispatch':
    case '/manager/maintenance':
    case '/manager/customers/historical':
    case '/manager/excel-transfer':
    case '/manager/technician-locations':
      if (currentRole != AppRole.manager && currentRole != AppRole.admin) {
        return _fallbackRouteForRole(currentRole);
      }
      break;

    case '/manager/customers':
    case '/manager/customers/new':
      if (currentRole != AppRole.manager && currentRole != AppRole.admin) {
        return _fallbackRouteForRole(currentRole);
      }
      break;

    case '/secretary/customers':
    case '/secretary/customers/new':
    case '/secretary/service-planning':
    case '/secretary/maintenance':
    case '/secretary/maintenance-assigned':
    case '/secretary/customers/historical':
    case '/secretary/follow-ups':
    case '/secretary/reports':
      if (currentRole != AppRole.secretary &&
          currentRole != AppRole.manager &&
          currentRole != AppRole.admin) {
        return _fallbackRouteForRole(currentRole);
      }
      break;

    case '/secretary/products':
    case '/secretary/payments':
      return currentRole == AppRole.secretary ? '/secretary-dashboard' : _fallbackRouteForRole(currentRole);

    case '/technician/customers':
      if (currentRole != AppRole.technician &&
          currentRole != AppRole.manager &&
          currentRole != AppRole.admin) {
        return _fallbackRouteForRole(currentRole);
      }
      break;

    default:
      if (_matchesRoute(matchedLocation, '/manager/service-requests')) {
        if (currentRole != AppRole.manager && currentRole != AppRole.admin) {
          return _fallbackRouteForRole(currentRole);
        }
      } else if (_matchesRoute(
        matchedLocation,
        '/secretary/service-requests',
      )) {
        if (currentRole != AppRole.secretary &&
            currentRole != AppRole.manager &&
            currentRole != AppRole.admin) {
          return _fallbackRouteForRole(currentRole);
        }
      } else if (_matchesRoute(matchedLocation, '/manager/customers')) {
        if (currentRole != AppRole.manager && currentRole != AppRole.admin) {
          return _fallbackRouteForRole(currentRole);
        }
      } else if (_matchesRoute(matchedLocation, '/secretary/customers')) {
        if (currentRole != AppRole.secretary &&
            currentRole != AppRole.manager &&
            currentRole != AppRole.admin) {
          return _fallbackRouteForRole(currentRole);
        }
      } else if (_matchesRoute(matchedLocation, '/secretary/follow-ups')) {
        if (currentRole != AppRole.secretary &&
            currentRole != AppRole.manager &&
            currentRole != AppRole.admin) {
          return _fallbackRouteForRole(currentRole);
        }
      } else if (_matchesRoute(matchedLocation, '/technician/jobs')) {
        if (currentRole != AppRole.technician &&
            currentRole != AppRole.manager &&
            currentRole != AppRole.admin) {
          return _fallbackRouteForRole(currentRole);
        }
      } else if (_matchesRoute(matchedLocation, '/technician/customers')) {
        if (currentRole != AppRole.technician &&
            currentRole != AppRole.manager &&
            currentRole != AppRole.admin) {
          return _fallbackRouteForRole(currentRole);
        }
      }
      break;
  }

  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/login',
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 48),
                  const SizedBox(height: 12),
                  const Text('Bu ekran açılamadı', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  const Text('Bağlantı eski veya ekran artık mevcut değil. Ana panele güvenli şekilde dönebilirsiniz.', textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () => context.go(_fallbackRouteForRole(authState.role)),
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('Ana Panele Dön'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    redirect: (context, state) {
      if (authState.status == AuthStatus.loading) {
        return null;
      }

      return resolveRouteRedirect(
        matchedLocation: state.matchedLocation,
        currentRole: authState.role,
        isAuthenticated: authState.isAuthenticated,
        isLoginRoute: state.matchedLocation == '/login',
      );
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationCenterScreen(),
      ),
      GoRoute(
        path: '/admin-dashboard',
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: '/secretary-dashboard',
        builder: (context, state) => const SecretaryDashboardScreen(),
      ),
      GoRoute(
        path: '/technician-dashboard',
        builder: (context, state) => const TechnicianDashboardScreen(),
      ),
      GoRoute(
        path: '/manager/users',
        builder: (context, state) => const UserManagementScreen(),
      ),
      GoRoute(
        path: '/manager/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/manager/service-form-designer',
        builder: (context, state) => const ServiceFormDesignerScreen(),
      ),

      GoRoute(
        path: '/manager/products',
        builder: (context, state) => const ProductManagementScreen(),
      ),
      GoRoute(
        path: '/manager/warehouses',
        builder: (context, state) => const WarehouseManagementScreen(),
      ),
      GoRoute(
        path: '/manager/stock-movements',
        builder: (context, state) => const InventoryStockMovementsScreen(),
      ),
      GoRoute(
        path: '/manager/payments',
        builder: (context, state) => const FinancePaymentsScreen(),
      ),
      GoRoute(
        path: '/manager/cash',
        builder: (context, state) => const CashRegisterScreen(role: AppRole.manager),
      ),
      GoRoute(
        path: '/manager/reports',
        builder: (context, state) => const ReportsScreen(),
      ),
      GoRoute(
        path: '/manager/excel-transfer',
        builder: (context, state) => const ExcelTransferScreen(),
      ),
      GoRoute(
        path: '/manager/dispatch',
        builder: (context, state) => const DispatchBoardScreen(),
      ),
      GoRoute(
        path: '/manager/technician-locations',
        builder: (context, state) => const TechnicianLocationsScreen(),
      ),
      GoRoute(
        path: '/manager/service-planning',
        builder: (context, state) => ServicePlanningScreen(
          initialFilter: state.uri.queryParameters['filter'],
          initialTechnician: state.uri.queryParameters['technician'],
        ),
      ),
      GoRoute(
        path: '/manager/service-documents',
        builder: (context, state) => const ServiceDocumentsScreen(),
      ),
      GoRoute(
        path: '/manager/maintenance',
        builder: (context, state) => const UpcomingMaintenanceScreen(role: AppRole.manager),
      ),
      GoRoute(
        path: '/manager/customers/historical',
        builder: (context, state) => const HistoricalCustomerScreen(role: AppRole.manager),
      ),
      GoRoute(
        path: '/portal/:token',
        builder: (context, state) => CustomerPortalScreen(
          token: state.pathParameters['token'] ?? '',
        ),
      ),

      GoRoute(
        path: '/manager/service-requests/pending',
        builder: (context, state) => const ServiceRequestListScreen(
          role: AppRole.manager,
          initialStatus: ServiceRequestStatus.pending,
        ),
      ),
      // Manager customers
      GoRoute(
        path: '/manager/customers',
        builder: (context, state) => CustomerListScreen(role: AppRole.manager),
      ),
      GoRoute(
        path: '/manager/customers/new',
        builder: (context, state) => CustomerFormScreen(role: AppRole.manager),
      ),
      GoRoute(
        path: '/manager/customers/:customerId',
        builder: (context, state) => CustomerDetailScreen(
          role: AppRole.manager,
          customerId: state.pathParameters['customerId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/manager/customers/:customerId/edit',
        builder: (context, state) => CustomerFormScreen(
          role: AppRole.manager,
          customerId: state.pathParameters['customerId'],
        ),
      ),

      // Manager service requests
      GoRoute(
        path: '/manager/service-requests',
        builder: (context, state) =>
            const ServiceRequestListScreen(role: AppRole.manager),
      ),
      GoRoute(
        path: '/manager/service-requests/new/:customerId',
        builder: (context, state) => ServiceRequestFormScreen(
          role: AppRole.manager,
          customerId: state.pathParameters['customerId'] ?? '',
        ),
      ),

      // Secretary customers
      GoRoute(
        path: '/secretary/customers/historical',
        builder: (context, state) =>
            const HistoricalCustomerScreen(role: AppRole.secretary),
      ),
      GoRoute(
        path: '/secretary/customers',
        builder: (context, state) =>
            CustomerListScreen(role: AppRole.secretary),
      ),
      GoRoute(
        path: '/secretary/customers/new',
        builder: (context, state) =>
            CustomerFormScreen(role: AppRole.secretary),
      ),
      GoRoute(
        path: '/secretary/customers/:customerId',
        builder: (context, state) => CustomerDetailScreen(
          role: AppRole.secretary,
          customerId: state.pathParameters['customerId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/secretary/customers/:customerId/edit',
        builder: (context, state) => CustomerFormScreen(
          role: AppRole.secretary,
          customerId: state.pathParameters['customerId'],
        ),
      ),

      // Secretary service requests
      GoRoute(
        path: '/secretary/service-requests',
        builder: (context, state) =>
            const ServiceRequestListScreen(role: AppRole.secretary),
      ),
      GoRoute(
        path: '/secretary/service-requests/new/:customerId',
        builder: (context, state) => ServiceRequestFormScreen(
          role: AppRole.secretary,
          customerId: state.pathParameters['customerId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/secretary/service-planning',
        builder: (context, state) => ServicePlanningScreen(
          initialFilter: state.uri.queryParameters['filter'],
          initialTechnician: state.uri.queryParameters['technician'],
        ),
      ),
      GoRoute(
        path: '/secretary/payments',
        builder: (context, state) => const FinancePaymentsScreen(),
      ),
      GoRoute(
        path: '/secretary/products',
        builder: (context, state) => const ProductManagementScreen(),
      ),
      GoRoute(
        path: '/secretary/maintenance',
        builder: (context, state) => const UpcomingMaintenanceScreen(role: AppRole.secretary),
      ),
      GoRoute(
        path: '/secretary/maintenance-assigned',
        builder: (context, state) => const UpcomingMaintenanceScreen(
          role: AppRole.secretary,
          assignedOnly: true,
        ),
      ),
      GoRoute(
        path: '/secretary/follow-ups',
        builder: (context, state) => const SecretaryFollowUpScreen(),
      ),
      GoRoute(
        path: '/secretary/follow-ups/:mode',
        builder: (context, state) => SecretaryFollowUpScreen(
          mode: state.pathParameters['mode'] ?? 'all',
        ),
      ),
      GoRoute(
        path: '/secretary/reports',
        builder: (context, state) => const SecretaryPerformanceScreen(),
      ),
      GoRoute(
        path: '/technician/cash',
        builder: (context, state) => const CashRegisterScreen(role: AppRole.technician),
      ),
      GoRoute(
        path: '/technician/jobs',
        builder: (context, state) => TechnicianJobsScreen(
          key: ValueKey(
            'technician-jobs-${state.uri.queryParameters['refresh'] ?? 'base'}',
          ),
        ),
      ),
      GoRoute(
        path: '/technician/jobs/:serviceRequestId',
        builder: (context, state) => ServiceExecutionScreen(
          serviceRequestId: state.pathParameters['serviceRequestId'] ?? '',
        ),
      ),

      // Technician customers
      GoRoute(
        path: '/technician/customers',
        redirect: (context, state) => '/technician/jobs',
      ),
      GoRoute(
        path: '/technician/customers/:customerId',
        builder: (context, state) => CustomerDetailScreen(
          role: AppRole.technician,
          customerId: state.pathParameters['customerId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/technician/customers/:customerId/edit',
        builder: (context, state) => CustomerFormScreen(
          role: AppRole.technician,
          customerId: state.pathParameters['customerId'],
        ),
      ),
    ],
  );
});
