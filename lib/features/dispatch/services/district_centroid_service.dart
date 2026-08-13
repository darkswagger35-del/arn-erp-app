import '../models/route_job.dart';

/// API/geocoder geçici olarak koordinat üretemediğinde rotayı kör bırakmamak
/// için il/ilçe merkezlerini coğrafi fallback olarak kullanır.
///
/// Bu bir "ilçe gruplama kuralı" değildir. Her ilçe gerçek yaklaşık enlem/
/// boylam noktasıyla temsil edilir ve SmartRoutePlanner yine Haversine mesafesi
/// üzerinden karar verir. Müşteri tablosunda gerçek koordinat varsa her zaman
/// bu fallback'in önüne geçer.
class DistrictCentroidService {
  const DistrictCentroidService();

  RoutePoint? resolve(String city, String district) {
    final key = '${_n(city)}|${_n(district)}';
    return _points[key];
  }

  String _n(String value) {
    return value
        .trim()
        .replaceAll('İ', 'I')
        .replaceAll('Ş', 'S')
        .replaceAll('Ğ', 'G')
        .replaceAll('Ü', 'U')
        .replaceAll('Ö', 'O')
        .replaceAll('Ç', 'C')
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ş', 's')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll('\u0307', '');
  }

  static const Map<String, RoutePoint> _points = {
    // İzmir
    'izmir|aliaga': RoutePoint(latitude: 38.7996, longitude: 26.9707),
    'izmir|balcova': RoutePoint(latitude: 38.3902, longitude: 27.0431),
    'izmir|bayindir': RoutePoint(latitude: 38.2174, longitude: 27.6484),
    'izmir|bayrakli': RoutePoint(latitude: 38.4622, longitude: 27.1666),
    'izmir|bergama': RoutePoint(latitude: 39.1207, longitude: 27.1805),
    'izmir|beydag': RoutePoint(latitude: 38.0827, longitude: 28.2098),
    'izmir|bornova': RoutePoint(latitude: 38.4626, longitude: 27.2200),
    'izmir|buca': RoutePoint(latitude: 38.3872, longitude: 27.1743),
    'izmir|cesme': RoutePoint(latitude: 38.3234, longitude: 26.3039),
    'izmir|cigli': RoutePoint(latitude: 38.4949, longitude: 27.0616),
    'izmir|dikili': RoutePoint(latitude: 39.0732, longitude: 26.8888),
    'izmir|foca': RoutePoint(latitude: 38.6703, longitude: 26.7566),
    'izmir|gaziemir': RoutePoint(latitude: 38.3214, longitude: 27.1277),
    'izmir|guzelbahce': RoutePoint(latitude: 38.3700, longitude: 26.8886),
    'izmir|karabaglar': RoutePoint(latitude: 38.3697, longitude: 27.1268),
    'izmir|karaburun': RoutePoint(latitude: 38.6377, longitude: 26.5111),
    'izmir|karsiyaka': RoutePoint(latitude: 38.4553, longitude: 27.1115),
    'izmir|kemalpasa': RoutePoint(latitude: 38.4262, longitude: 27.4170),
    'izmir|kinik': RoutePoint(latitude: 39.0875, longitude: 27.3836),
    'izmir|kiraz': RoutePoint(latitude: 38.2307, longitude: 28.2045),
    'izmir|konak': RoutePoint(latitude: 38.4189, longitude: 27.1287),
    'izmir|menderes': RoutePoint(latitude: 38.2540, longitude: 27.1344),
    'izmir|menemen': RoutePoint(latitude: 38.6070, longitude: 27.0694),
    'izmir|narlidere': RoutePoint(latitude: 38.3927, longitude: 27.0048),
    'izmir|odemis': RoutePoint(latitude: 38.2278, longitude: 27.9696),
    'izmir|seferihisar': RoutePoint(latitude: 38.1975, longitude: 26.8388),
    'izmir|selcuk': RoutePoint(latitude: 37.9494, longitude: 27.3685),
    'izmir|tire': RoutePoint(latitude: 38.0888, longitude: 27.7351),
    'izmir|torbali': RoutePoint(latitude: 38.1590, longitude: 27.3578),
    'izmir|urla': RoutePoint(latitude: 38.3229, longitude: 26.7640),

    // Aydın
    'aydin|efeler': RoutePoint(latitude: 37.8450, longitude: 27.8396),
    'aydin|merkez': RoutePoint(latitude: 37.8450, longitude: 27.8396),
    'aydin|bozdogan': RoutePoint(latitude: 37.6716, longitude: 28.3136),
    'aydin|buharkent': RoutePoint(latitude: 37.9636, longitude: 28.7427),
    'aydin|cine': RoutePoint(latitude: 37.6117, longitude: 28.0610),
    'aydin|didim': RoutePoint(latitude: 37.3763, longitude: 27.2678),
    'aydin|germencik': RoutePoint(latitude: 37.8706, longitude: 27.6022),
    'aydin|incirliova': RoutePoint(latitude: 37.8520, longitude: 27.7237),
    'aydin|karacasu': RoutePoint(latitude: 37.7280, longitude: 28.6058),
    'aydin|karpuzlu': RoutePoint(latitude: 37.5581, longitude: 27.8345),
    'aydin|kocarli': RoutePoint(latitude: 37.7614, longitude: 27.7051),
    'aydin|kosk': RoutePoint(latitude: 37.8536, longitude: 28.0512),
    'aydin|kusadasi': RoutePoint(latitude: 37.8597, longitude: 27.2595),
    'aydin|kuyucak': RoutePoint(latitude: 37.9132, longitude: 28.4592),
    'aydin|nazilli': RoutePoint(latitude: 37.9163, longitude: 28.3228),
    'aydin|soke': RoutePoint(latitude: 37.7517, longitude: 27.4103),
    'aydin|sultanhisar': RoutePoint(latitude: 37.8897, longitude: 28.1545),
    'aydin|yenipazar': RoutePoint(latitude: 37.8243, longitude: 28.1973),

    // Manisa - uygulamada sık kullanılan ana ilçeler
    'manisa|sehzadeler': RoutePoint(latitude: 38.6140, longitude: 27.4296),
    'manisa|yunusemre': RoutePoint(latitude: 38.6320, longitude: 27.4040),
    'manisa|akhisar': RoutePoint(latitude: 38.9185, longitude: 27.8401),
    'manisa|turgutlu': RoutePoint(latitude: 38.5008, longitude: 27.7058),
    'manisa|salihli': RoutePoint(latitude: 38.4826, longitude: 28.1384),
  };
}
