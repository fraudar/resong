// language: Dart, file: lib/core/artwork_url.dart, target: mobile + desktop, runtime: resong app
/// Reescreve URLs de capa para uma resolução maior sem trocar a fonte.
///
/// O YT Music entrega `yt3.googleusercontent.com/...=w120-h120-l90-rj` no
/// feed — 120 px esticados no player viram borrão. O parâmetro de tamanho do
/// proxy do Google é livre, então basta pedir o tamanho que a UI vai exibir.
String? upgradeArtworkUrl(String? url, {int px = 544}) {
  if (url == null) return null;
  var u = url.trim();
  if (u.isEmpty) return u;

  final size = px < 64 ? 64 : (px > 1200 ? 1200 : px);
  final host = Uri.tryParse(u)?.host ?? '';

  if (host.endsWith('googleusercontent.com') || host.endsWith('ggpht.com')) {
    final eq = u.lastIndexOf('=');
    if (eq > u.lastIndexOf('/')) {
      final suffix = u.substring(eq + 1);
      final m = RegExp(r'^([whs])\d+(?:-[whs]\d+)*').firstMatch(suffix);
      if (m != null) {
        final after = suffix.substring(m.end);
        if (m.group(1) == 's') {
          return '${u.substring(0, eq)}=s$size$after';
        }
        return '${u.substring(0, eq)}=w$size-h$size$after';
      }
    }
    return '$u=w$size-h$size-l90-rj';
  }

  if (host.endsWith('sndcdn.com')) {
    return u.replaceAll(RegExp(r'-(?:large|t\d+x\d+|crop|badge)\.'), '-t500x500.');
  }

  if (host.contains('audius') || u.contains('/content/')) {
    return u.replaceAll(RegExp(r'/(?:150x150|480x480|1000x1000)\.'), '/1000x1000.');
  }

  return u;
}
