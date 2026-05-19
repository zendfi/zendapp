import 'package:flutter/material.dart';
import '../../design/zend_primitives.dart';
import '../../design/zend_tokens.dart';
import '../../services/api_client.dart';

class CryptoChainSelectionStep extends StatefulWidget {
  const CryptoChainSelectionStep({
    super.key,
    required this.onSkip,
    required this.onComplete,
    required this.apiClient,
  });

  final VoidCallback onSkip;
  final VoidCallback onComplete;
  final ApiClient apiClient;

  @override
  State<CryptoChainSelectionStep> createState() =>
      _CryptoChainSelectionStepState();
}

class _CryptoChainSelectionStepState extends State<CryptoChainSelectionStep> {
  List<Map<String, dynamic>> _chains = [];
  final Set<int> _selectedChainIds = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadChains();
  }

  Future<void> _loadChains() async {
    try {
      final chains = await widget.apiClient.getSupportedChains();
      if (!mounted) return;
      setState(() {
        _chains = chains;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load chains.';
      });
    }
  }

  void _onDone() {
    if (_selectedChainIds.isNotEmpty) {
      // Fire and forget — do NOT await
      widget.apiClient
          .setOnboardingChains(_selectedChainIds.toList())
          .catchError((_) {});
    }
    widget.onComplete();
  }

  Widget _buildChainList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: const TextStyle(
                fontFamily: 'DMSans',
                fontSize: 14,
                color: ZendColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _loadChains();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _chains.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, color: ZendColors.border),
      itemBuilder: (context, index) {
        final chain = _chains[index];
        final chainId = chain['chain_id'] as int;
        final displayName = chain['display_name'] as String? ?? '';
        final symbol = chain['symbol'] as String? ?? '';
        final blockchainName = chain['blockchain_name'] as String? ?? '';
        final initial = blockchainName.isNotEmpty
            ? blockchainName[0].toUpperCase()
            : displayName.isNotEmpty
                ? displayName[0].toUpperCase()
                : '?';
        final isSelected = _selectedChainIds.contains(chainId);

        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: ZendColors.bgSecondary,
            child: Text(
              initial,
              style: const TextStyle(
                fontFamily: 'DMSans',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: ZendColors.textPrimary,
              ),
            ),
          ),
          title: Text(
            displayName,
            style: const TextStyle(
              fontFamily: 'DMSans',
              fontSize: 15,
              color: ZendColors.textPrimary,
            ),
          ),
          subtitle: Text(
            symbol,
            style: const TextStyle(
              fontFamily: 'DMSans',
              fontSize: 12,
              color: ZendColors.textSecondary,
            ),
          ),
          trailing: Checkbox(
            value: isSelected,
            activeColor: ZendColors.accent,
            onChanged: (v) => setState(() {
              if (v == true) {
                _selectedChainIds.add(chainId);
              } else {
                _selectedChainIds.remove(chainId);
              }
            }),
          ),
          onTap: () => setState(() {
            if (isSelected) {
              _selectedChainIds.remove(chainId);
            } else {
              _selectedChainIds.add(chainId);
            }
          }),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final zt = ZendTheme.of(context);

    return Scaffold(
      backgroundColor: zt.bgPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Text(
                'One last step!',
                style: TextStyle(
                  fontFamily: 'InstrumentSerif',
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: zt.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Would you be receiving or sending crypto on any of these chains? "
                "We'll set up your deposit addresses in the background.",
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 14,
                  color: zt.textSecondary,
                ),
              ),
              const SizedBox(height: 24),

              // Chain list
              Expanded(child: _buildChainList()),

              const SizedBox(height: 24),

              // Bottom actions
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: widget.onSkip,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: zt.textPrimary,
                          side: BorderSide(color: zt.border),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(ZendRadii.lg),
                          ),
                        ),
                        child: const Text(
                          'Skip',
                          style: TextStyle(
                            fontFamily: 'DMSans',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: PrimaryButton(
                      label: _selectedChainIds.isEmpty ? 'Maybe later' : 'Done',
                      onPressed: _onDone,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
