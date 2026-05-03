import 'package:flutter/material.dart';
import '../../utils/design_system.dart';
import '../../utils/responsive.dart';
import 'landing_footer.dart';

class FooterContentPage extends StatelessWidget {
  final FooterContentData data;
  const FooterContentPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const _FooterTopBar(),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: Responsive.isMobile(context) ? 20 : 60, vertical: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 40)),
                  const SizedBox(height: 8),
                  Text('Last updated: March 2026', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 28),
                  ...data.paragraphs.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${e.key + 1}. ${_sectionTitleFor(data.title, e.key)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                        const SizedBox(height: 10),
                        Text(e.value, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.7)),
                      ],
                    ),
                  )),
                  const SizedBox(height: 32),
                  const LandingFooter(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FooterContentData {
  final String title;
  final String subtitle;
  final List<String> paragraphs;
  const FooterContentData({required this.title, required this.subtitle, required this.paragraphs});
}

class FooterContentCatalog {
  static const streaming = FooterContentData(
    title: 'Streaming',
    subtitle: 'Unlock global entertainment without limits',
    paragraphs: [
      'Streaming Mode allows users to bypass geo-restrictions and access content from different countries seamlessly. It ensures stable, high-speed connections optimized for platforms like Netflix, Disney+, and Amazon Prime, delivering uninterrupted playback and enhanced viewing experiences worldwide without buffering.',
      'With dedicated streaming servers, users can connect to regions where specific shows or movies are available. This removes restrictions imposed by content licensing, allowing complete freedom to explore global entertainment libraries without limitations or interruptions.',
      'The VPN intelligently routes traffic through optimized servers designed specifically for streaming. This reduces latency and buffering, ensuring smooth playback even in high-definition formats such as 4K and HDR content.',
      'Streaming Mode also helps users maintain privacy while watching content online. Internet service providers often monitor streaming activity, but VPN encryption ensures that browsing and viewing habits remain completely secure and hidden.',
      'Users traveling abroad can access their home country’s streaming services easily. This ensures continuity of entertainment without needing to switch accounts or deal with location-based restrictions imposed by streaming platforms.',
      'The system automatically detects streaming activity and suggests the best server for optimal performance. This smart optimization enhances user experience by reducing manual configuration and ensuring consistent streaming quality.',
      'Streaming Mode supports multiple devices simultaneously, allowing families or groups to enjoy content on smartphones, tablets, and smart TVs without compromising speed or performance across connections.',
      'By avoiding ISP throttling, users can enjoy consistent speeds even during peak hours. This ensures that streaming performance remains stable regardless of network congestion or high traffic periods.',
      'Advanced encryption ensures secure streaming even on public Wi‑Fi networks. Users can safely access their favorite platforms in cafes, airports, or hotels without risking data exposure or cyber threats.',
      'Streaming Mode transforms the VPN into an entertainment powerhouse, combining speed, accessibility, and privacy into a seamless experience that enhances how users consume global digital content.',
    ],
  );

  static const gaming = FooterContentData(
    title: 'Gaming',
    subtitle: 'Low latency and uninterrupted gameplay',
    paragraphs: [
      'Gaming Mode is designed to deliver ultra‑low latency connections, ensuring smooth gameplay without lag. It uses optimized routing paths to connect players to game servers faster, improving response times and overall performance during competitive gaming sessions.',
      'The VPN protects gamers from DDoS attacks, which are common in online multiplayer environments. By masking IP addresses, it prevents malicious users from targeting players and disrupting their gaming experience.',
      'Gaming Mode enhances connection stability by reducing packet loss and jitter. This ensures consistent gameplay, especially in fast‑paced games where milliseconds can determine the outcome of a match.',
      'Players can access region‑locked games or servers using VPN technology. This allows gamers to explore international servers, compete globally, and experience new gaming environments without restrictions.',
      'The system prioritizes gaming traffic over other data, ensuring that gameplay remains uninterrupted even when multiple applications are running simultaneously on the device.',
      'Gaming Mode also helps reduce ISP throttling, which can slow down gaming connections. By encrypting traffic, it prevents ISPs from identifying and limiting gaming‑related data usage.',
      'Cross‑platform compatibility allows gamers to use the VPN on PCs, consoles, and mobile devices. This ensures a consistent gaming experience regardless of the platform being used.',
      'The VPN provides dedicated gaming servers in key regions worldwide. This allows players to connect to the nearest or most efficient server for optimal performance and reduced latency.',
      'With automatic server switching, the VPN selects the best route during gameplay. This ensures uninterrupted sessions even if network conditions change dynamically.',
      'Gaming Mode empowers players with faster speeds, better security, and global access, making it an essential tool for both casual gamers and professional esports competitors.',
    ],
  );

  static const crypto = FooterContentData(
    title: 'Crypto',
    subtitle: 'Secure your digital assets and transactions',
    paragraphs: [
      'Crypto Mode focuses on protecting users involved in cryptocurrency trading and transactions. It ensures secure connections to exchanges and wallets, reducing the risk of hacking, phishing, and data interception.',
      'The VPN encrypts all data transmitted during crypto transactions, ensuring that sensitive information such as private keys and login credentials remains protected from cyber threats.',
      'Crypto Mode prevents tracking of blockchain‑related activities by hiding user IP addresses. This enhances anonymity and protects users from surveillance or targeted attacks.',
      'Users can safely access crypto exchanges even on public Wi‑Fi networks. The VPN ensures that all communications are encrypted, preventing hackers from intercepting sensitive data.',
      'Anti‑phishing protection blocks access to malicious websites that mimic legitimate crypto platforms. This helps users avoid scams and secure their investments.',
      'The VPN supports multiple crypto platforms, ensuring compatibility with popular exchanges and wallets. This allows seamless integration into existing trading workflows.',
      'Crypto Mode reduces the risk of geo‑restrictions imposed by certain exchanges. Users can access services that may be limited in their region without compromising security.',
      'The system provides alerts for suspicious activity, helping users stay informed about potential threats. This proactive approach enhances overall security.',
      'By masking IP addresses, the VPN ensures that transaction patterns cannot be easily traced back to users, adding an extra layer of privacy.',
      'Crypto Mode is essential for anyone dealing with digital assets, offering a secure, private, and reliable environment for managing cryptocurrency activities.',
    ],
  );

  static const torrenting = FooterContentData(
    title: 'Torrenting',
    subtitle: 'Fast and anonymous file sharing',
    paragraphs: [
      'Torrenting Mode ensures secure peer‑to‑peer file sharing by masking IP addresses and encrypting data. This protects users from tracking and potential legal risks associated with downloading or sharing files online.',
      'The VPN provides high‑speed servers optimized for torrenting, ensuring fast download and upload speeds without interruptions or throttling from internet service providers.',
      'Users can maintain complete anonymity while torrenting, as their real IP address remains hidden. This prevents third parties from monitoring their activities.',
      'The system supports popular torrent clients, allowing seamless integration without requiring additional configuration or technical expertise.',
      'Torrenting Mode prevents ISP throttling, ensuring consistent speeds even during large file transfers or peak usage periods.',
      'Advanced encryption protects data packets from interception, ensuring secure file sharing even on unsecured networks.',
      'The VPN includes a kill switch feature that disconnects the internet if the VPN connection drops, preventing accidental exposure of user identity.',
      'Users can access torrent sites that may be restricted in certain regions, ensuring uninterrupted access to content.',
      'The VPN ensures compliance with privacy standards, giving users peace of mind while engaging in file‑sharing activities.',
      'Torrenting Mode combines speed, privacy, and security, making it a reliable solution for safe and efficient file sharing.',
    ],
  );

  static const privacy = FooterContentData(
    title: 'Privacy',
    subtitle: 'Protect your identity and online activity',
    paragraphs: [
      'Privacy is a fundamental right in the digital world, and VPN technology ensures that users can browse the internet without being tracked. It encrypts all data, preventing third parties from accessing personal information or monitoring online behavior.',
      'Internet service providers often collect and store user data, including browsing history. A VPN prevents this by masking the user’s IP address, ensuring that online activities remain private and secure from unwanted surveillance.',
      'Public Wi‑Fi networks are highly vulnerable to cyber threats. VPN encryption protects users by securing data transmissions, preventing hackers from intercepting sensitive information such as passwords, emails, and financial details.',
      'Privacy tools such as tracker blockers and ad blockers enhance online security. These features prevent websites from collecting user data and reduce exposure to intrusive advertisements and malicious scripts.',
      'A VPN ensures anonymity by routing traffic through secure servers located in different regions. This makes it difficult for anyone to trace online activity back to the user’s actual location or identity.',
      'With increasing cyber threats, protecting personal data has become essential. VPNs provide a strong layer of defense against identity theft, data breaches, and unauthorized access.',
      'Privacy‑focused VPNs follow strict no‑logs policies, ensuring that user activity is not recorded or stored. This guarantees complete confidentiality and trust.',
      'Users can safely access restricted or censored content without exposing their identity. VPNs help maintain freedom of information while protecting user privacy.',
      'Advanced encryption standards ensure that even sophisticated cyberattacks cannot compromise user data. This makes VPNs a reliable tool for secure internet usage.',
      'Privacy is not optional in today’s digital age. A VPN empowers users to take control of their data and maintain complete anonymity online.',
    ],
  );

  static const howVpnWorks = FooterContentData(
    title: 'How VPN Works',
    subtitle: 'Understanding the technology behind VPN security',
    paragraphs: [
      'A VPN works by creating a secure tunnel between the user’s device and a remote server. All internet traffic passes through this encrypted tunnel, ensuring that data remains protected from interception or unauthorized access.',
      'When a user connects to a VPN, their real IP address is replaced with the IP address of the VPN server. This helps mask their identity and location, enhancing privacy and anonymity online.',
      'Encryption is a key component of VPN technology. It converts data into unreadable code, ensuring that even if intercepted, the information cannot be accessed without proper decryption.',
      'VPN protocols such as WireGuard and OpenVPN determine how data is transmitted securely. These protocols ensure speed, reliability, and strong encryption standards.',
      'The VPN server acts as an intermediary between the user and the internet. Websites only see the server’s IP address, not the user’s actual identity.',
      'DNS requests are also routed through the VPN, preventing leaks that could reveal user activity. This ensures complete privacy during browsing sessions.',
      'VPNs can bypass geo‑restrictions by allowing users to connect to servers in different countries. This makes it appear as if they are accessing the internet from another location.',
      'A kill switch feature ensures that if the VPN connection drops, the internet connection is automatically disabled. This prevents accidental exposure of user data.',
      'Split tunneling allows users to choose which apps use the VPN and which connect directly to the internet. This provides flexibility and optimized performance.',
      'Overall, VPN technology combines encryption, secure servers, and intelligent routing to provide a safe and private internet experience.',
    ],
  );

  static const whyVpn = FooterContentData(
    title: 'Why VPN?',
    subtitle: 'Why you need a VPN in today’s digital world',
    paragraphs: [
      'A VPN is essential for protecting personal data from hackers and cyber threats. It ensures that sensitive information remains secure, especially when using public networks or accessing confidential services.',
      'Online privacy is increasingly under threat due to tracking and data collection. A VPN helps users maintain anonymity and prevent unauthorized monitoring of their online activities.',
      'Many websites and services restrict content based on location. A VPN allows users to bypass these restrictions and access global content without limitations.',
      'ISPs often throttle internet speeds based on usage patterns. A VPN prevents this by encrypting traffic, ensuring consistent and faster connections.',
      'Remote workers benefit from VPNs by securely accessing company resources. This ensures data protection and secure communication across networks.',
      'VPNs protect against cyberattacks such as man‑in‑the‑middle attacks. This is especially important when using unsecured public Wi‑Fi networks.',
      'Gamers and streamers can enhance their experience with optimized servers and reduced latency. VPNs improve both performance and accessibility.',
      'Cryptocurrency users can protect transactions and prevent tracking. This adds an extra layer of security for financial activities.',
      'A VPN helps maintain digital freedom by bypassing censorship and accessing restricted content safely.',
      'In a world where data is constantly at risk, a VPN is a necessary tool for secure and unrestricted internet access.',
    ],
  );

  static const vpnGuide = FooterContentData(
    title: 'VPN Guide 2024',
    subtitle: 'Complete beginner’s guide to using a VPN',
    paragraphs: [
      'A VPN, or Virtual Private Network, is a tool that protects your internet connection and ensures privacy. It encrypts data and hides your IP address, making online activities secure and anonymous.',
      'To get started, users need to download a VPN app and create an account. Most VPNs offer both free and paid plans with varying features.',
      'After installation, users can connect to a server of their choice. This determines the virtual location from which they access the internet.',
      'Beginners should choose servers close to their location for better speed. For streaming or gaming, specialized servers provide optimized performance.',
      'VPN settings allow customization such as protocol selection and auto‑connect options. These features enhance usability and security.',
      'It is important to enable the kill switch feature to prevent data leaks if the connection drops unexpectedly.',
      'Users should avoid free VPNs with weak security or unclear privacy policies. Choosing a trusted provider ensures better protection.',
      'VPNs can be used on multiple devices including smartphones, laptops, and smart TVs. This ensures complete coverage across devices.',
      'Regular updates improve security and performance. Users should keep their VPN app updated at all times.',
      'By understanding basic features and best practices, users can maximize the benefits of a VPN for secure browsing.',
    ],
  );

  static const blog = FooterContentData(
    title: 'Blog',
    subtitle: 'Insights, updates, and cybersecurity tips',
    paragraphs: [
      'The blog section provides valuable insights into online security, privacy trends, and VPN usage. It helps users stay informed about the latest developments in cybersecurity.',
      'Regular updates include tips on safe browsing, avoiding scams, and protecting personal data from cyber threats.',
      'Blog articles explain complex topics in simple language, making it easier for beginners to understand VPN technology and its benefits.',
      'Users can learn about new features and updates introduced in the VPN application through blog posts.',
      'The blog also covers comparisons between different VPN services, helping users make informed decisions.',
      'Educational content includes guides on streaming, gaming, and crypto security using VPN technology.',
      'Cybersecurity news keeps users aware of emerging threats and how to stay protected online.',
      'Expert opinions and case studies provide deeper insights into digital privacy and security practices.',
      'The blog encourages user engagement through comments and feedback, creating a community around online safety.',
      'Overall, the blog serves as a knowledge hub for anyone interested in improving their online security.',
    ],
  );

  static const press = FooterContentData(
    title: 'Press',
    subtitle: 'Media coverage and company announcements',
    paragraphs: [
      'The press section highlights media coverage, announcements, and milestones achieved by the VPN company. It showcases growth, innovation, and industry recognition.',
      'Journalists and media professionals can access official statements and press releases in this section.',
      'The press page provides insights into new product launches and feature updates.',
      'Company achievements and awards are highlighted to build credibility and trust among users.',
      'Partnerships and collaborations are also announced through press releases.',
      'Media kits and resources are available for journalists to use in publications.',
      'The press section ensures transparency by sharing company updates publicly.',
      'It helps build brand reputation and authority in the cybersecurity industry.',
      'Users can stay informed about the company’s progress and future plans.',
      'The press section acts as a bridge between the company and the media.',
    ],
  );

  static const affiliates = FooterContentData(
    title: 'Affiliates',
    subtitle: 'Earn by promoting our VPN',
    paragraphs: [
      'The affiliate program allows individuals and businesses to earn commissions by promoting the VPN service.',
      'Affiliates receive unique referral links to track conversions and earnings.',
      'Competitive commission rates make the program attractive for marketers and influencers.',
      'Marketing materials such as banners and content are provided to affiliates.',
      'Affiliates can promote through blogs, social media, and websites.',
      'Real‑time dashboards allow tracking of performance and earnings.',
      'The program supports global affiliates with flexible payout options.',
      'Training resources help affiliates maximize conversions.',
      'Long‑term partnerships are encouraged through incentives and bonuses.',
      'The affiliate program is a great opportunity to earn passive income.',
    ],
  );

  static const noLogsAudit = FooterContentData(
    title: 'No‑Logs Audit',
    subtitle: 'Transparency you can trust',
    paragraphs: [
      'A no‑logs policy ensures that user activity is not recorded or stored by the VPN provider.',
      'Independent audits verify the authenticity of the no‑logs claim.',
      'This builds trust and credibility among users concerned about privacy.',
      'Audit reports are published publicly for transparency.',
      'The system is designed to operate without storing sensitive user data.',
      'Regular audits ensure ongoing compliance with privacy standards.',
      'Users can confidently use the VPN without fear of data tracking.',
      'The no‑logs policy is a key feature of privacy‑focused VPNs.',
      'Third‑party verification ensures unbiased evaluation.',
      'Transparency is essential for maintaining user trust.',
    ],
  );

  static const gdpr = FooterContentData(
    title: 'GDPR',
    subtitle: 'Compliant with global data protection standards',
    paragraphs: [
      'GDPR ensures that user data is handled responsibly and securely.',
      'The VPN complies with data protection regulations to protect user rights.',
      'Users have control over their personal data and how it is used.',
      'Data collection is minimized and clearly explained.',
      'Users can request access or deletion of their data.',
      'Strong encryption ensures compliance with security standards.',
      'Privacy policies are transparent and easy to understand.',
      'The VPN follows strict guidelines for data processing.',
      'Compliance builds trust with users worldwide.',
      'GDPR ensures accountability ..........and responsibility in data handling.',
    ],
  );
}

String _sectionTitleFor(String pageTitle, int index) {
  const titles = {
    'Streaming': [
      'Introduction',
      'Global Access',
      'Optimized Routing',
      'Private Viewing',
      'Travel Ready',
      'Smart Optimization',
      'Multi‑Device Support',
      'No Throttling',
      'Secure on Public Wi‑Fi',
      'Entertainment without Limits',
    ],
    'Gaming': [
      'Ultra‑Low Latency',
      'DDoS Protection',
      'Stable Connections',
      'Region Access',
      'Traffic Prioritization',
      'Anti‑Throttling',
      'Cross‑Platform Play',
      'Dedicated Servers',
      'Auto Switching',
      'Competitive Edge',
    ],
    'Crypto': [
      'Secure Connections',
      'Encrypted Transactions',
      'Anonymity Shield',
      'Public Wi‑Fi Safety',
      'Anti‑Phishing',
      'Exchange Compatibility',
      'Bypass Restrictions',
      'Threat Alerts',
      'Privacy Layer',
      'Trusted Crypto Workflow',
    ],
    'Torrenting': [
      'Private Sharing',
      'High‑Speed Servers',
      'Full Anonymity',
      'Client Friendly',
      'No ISP Throttling',
      'Encrypted Packets',
      'Kill Switch',
      'Access Anywhere',
      'Privacy Compliance',
      'Fast and Safe',
    ],
    'Privacy': [
      'Right to Privacy',
      'ISP Shield',
      'Public Wi‑Fi Protection',
      'Tracker Blocking',
      'Anonymity by Design',
      'Defense Against Threats',
      'No‑Logs Policy',
      'Freedom of Access',
      'Strong Encryption',
      'Take Back Control',
    ],
    'How VPN Works': [
      'Secure Tunnel',
      'IP Masking',
      'Encryption',
      'Protocols',
      'Server Mediation',
      'DNS Protection',
      'Geo‑Bypass',
      'Kill Switch',
      'Split Tunneling',
      'Private Internet',
    ],
    'Why VPN?': [
      'Protect Your Data',
      'Privacy from Tracking',
      'Access Everywhere',
      'No ISP Throttling',
      'Remote Work Safety',
      'Defend Against Attacks',
      'Better Gaming',
      'Crypto Security',
      'Bypass Censorship',
      'Essential Security',
    ],
    'VPN Guide 2024': [
      'What a VPN Is',
      'Getting Started',
      'Choosing a Server',
      'Speed Tips',
      'Settings & Protocols',
      'Use a Kill Switch',
      'Avoid Weak Providers',
      'Multi‑Device Use',
      'Keep It Updated',
      'Best Practices',
    ],
    'Blog': [
      'Security Insights',
      'Safety Tips',
      'Simple Explanations',
      'Product Updates',
      'Comparisons',
      'Use‑Case Guides',
      'Threat News',
      'Expert Opinions',
      'Community Learning',
      'Knowledge Hub',
    ],
    'Press': [
      'Media Coverage',
      'Press Releases',
      'Product Launches',
      'Awards & Recognition',
      'Partnerships',
      'Media Kits',
      'Transparency',
      'Brand Authority',
      'Company Updates',
      'Media Bridge',
    ],
    'Affiliates': [
      'Earn Commissions',
      'Referral Links',
      'Competitive Rates',
      'Marketing Assets',
      'Flexible Channels',
      'Real‑Time Tracking',
      'Global Payouts',
      'Training Resources',
      'Long‑Term Incentives',
      'Passive Income',
    ],
    'No‑Logs Audit': [
      'No‑Logs Policy',
      'Independent Audits',
      'Trust & Credibility',
      'Public Reports',
      'Minimal Data',
      'Ongoing Compliance',
      'Confident Usage',
      'Privacy‑Focused',
      'Third‑Party Verification',
      'Transparency',
    ],
    'GDPR': [
      'Data Protection',
      'User Rights',
      'User Control',
      'Minimal Collection',
      'Access & Deletion',
      'Encryption Standards',
      'Transparent Policies',
      'Processing Rules',
      'Trust Worldwide',
      'Accountability',
    ],
  };

  final list = titles[pageTitle];
  if (list == null || index >= list.length) return 'Section';
  return list[index];
}

class _FooterTopBar extends StatelessWidget {
  const _FooterTopBar();

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 60, vertical: isMobile ? 14 : 20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
      ),
      child: isMobile
          ? Row(children: [
              _LogoHomeLink(),
              const Spacer(),
              Text('/ Info', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12)),
              const SizedBox(width: 10),
              const _NavMenu(title: 'Info'),
            ])
          : Row(children: [
              _LogoHomeLink(),
              const SizedBox(width: 32),
              Text('/ Info', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14)),
              const Spacer(),
              _NavChip('Features', '/features', context),
              _NavChip('Pricing', '/pricing', context),
              _NavChip('Servers', '/servers', context),
              const SizedBox(width: 20),
              TextButton(onPressed: () => Navigator.pushNamed(context, '/login'), child: const Text('Log In', style: TextStyle(color: Colors.white70))),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, '/signup'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Get Started', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ]),
    );
  }
}

class _FooterBottomBar extends StatelessWidget {
  const _FooterBottomBar();

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Container(
      padding: EdgeInsets.symmetric(vertical: 28, horizontal: isMobile ? 16 : 60),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05)))),
      child: isMobile
          ? Column(children: [
              Text('© 2026 SecureVPN Ltd.', style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: ['/privacy-policy', '/terms', '/cookie-policy'].map((r) => TextButton(
                  onPressed: () => Navigator.pushNamed(context, r),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    r.replaceAll('-', ' ').replaceAll('/', '').replaceFirst(r[1], r[1].toUpperCase()),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
                  ),
                )).toList(),
              ),
            ])
          : Row(
              children: [
                Text('© 2026 SecureVPN Ltd.', style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12)),
                const Spacer(),
                ...['/privacy-policy', '/terms', '/cookie-policy'].map((r) => TextButton(
                  onPressed: () => Navigator.pushNamed(context, r),
                  child: Text(r.replaceAll('-', ' ').replaceAll('/', '').replaceFirst(r[1], r[1].toUpperCase()), style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12)),
                )),
              ],
            ),
    );
  }
}

Widget _NavChip(String label, String route, BuildContext context) => TextButton(
  onPressed: () => Navigator.pushNamed(context, route),
  child: Text(label, style: const TextStyle(color: Colors.white60, fontSize: 14)),
);

class _LogoHomeLink extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.shield_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Text('SecureVPN', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
        ]),
      ),
    );
  }
}

class _NavMenu extends StatelessWidget {
  final String title;
  const _NavMenu({required this.title});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Menu',
      color: AppColors.cardBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      offset: const Offset(0, 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      constraints: const BoxConstraints(minWidth: 200),
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: const Icon(Icons.menu_rounded, color: Colors.white, size: 20),
      ),
      onSelected: (value) {
        if (value.startsWith('route:')) {
          Navigator.pushNamed(context, value.replaceFirst('route:', ''));
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          height: 44,
          value: 'title',
          child: Row(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            const Text('Navigate', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ]),
        ),
        PopupMenuItem<String>(
          enabled: false,
          height: 28,
          value: 'subtitle',
          child: Text('/ $title', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
        ),
        const PopupMenuDivider(height: 12),
        PopupMenuItem<String>(value: 'route:/features', height: 44, child: _MenuRow(icon: Icons.auto_awesome_rounded, label: 'Features')),
        PopupMenuItem<String>(value: 'route:/pricing', height: 44, child: _MenuRow(icon: Icons.payments_rounded, label: 'Pricing')),
        PopupMenuItem<String>(value: 'route:/servers', height: 44, child: _MenuRow(icon: Icons.public_rounded, label: 'Servers')),
        const PopupMenuDivider(height: 12),
        PopupMenuItem<String>(value: 'route:/login', height: 44, child: _MenuRow(icon: Icons.login_rounded, label: 'Log In')),
        PopupMenuItem<String>(
          value: 'route:/signup',
          height: 46,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(children: [
              Icon(Icons.bolt_rounded, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Text('Get Started', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            ]),
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MenuRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Icon(icon, color: Colors.white, size: 16),
      ),
      const SizedBox(width: 10),
      Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
    ]);
  }
}
