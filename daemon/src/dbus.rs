use crate::core::QuickShareCore;
use log::{error, info};
use std::sync::Arc;
use zbus::{interface, SignalContext};

pub struct QuickShareDBus {
    pub core: Arc<QuickShareCore>,
}

#[interface(name = "org.danklinux.QuickShare")]
impl QuickShareDBus {
    async fn set_visibility(&self, visible: bool) -> zbus::fdo::Result<()> {
        self.core.set_visibility(visible).map_err(|e| {
            error!("{}", e);
            zbus::fdo::Error::Failed(e.to_string())
        })
    }

    async fn start_discovery(&self, #[zbus(signal_context)] ctxt: SignalContext<'_>) -> zbus::fdo::Result<()> {
        let mut dch_receiver = self.core.start_discovery().map_err(|e| {
            error!("{}", e);
            zbus::fdo::Error::Failed(e.to_string())
        })?;

        let ctxt = ctxt.into_owned();
        tokio::spawn(async move {
            while let Ok(endpoint) = dch_receiver.recv().await {
                let name = endpoint.name.unwrap_or_else(|| "Unknown Device".to_string());
                let ip = endpoint.ip.unwrap_or_else(|| "".to_string());
                info!("Discovered device: {} ({}) at {}", name, endpoint.id, ip);
                
                if let Err(e) = QuickShareDBus::device_discovered(&ctxt, &endpoint.id, &name, &ip).await {
                    error!("Failed to emit device_discovered signal: {}", e);
                }
            }
        });
        
        Ok(())
    }

    async fn send_files(&self, device_id: String, device_name: String, ip_addr: String, files: Vec<String>) -> zbus::fdo::Result<()> {
        self.core.send_files(device_id, device_name, ip_addr, files).await.map_err(|e| {
            error!("{}", e);
            zbus::fdo::Error::Failed(e.to_string())
        })
    }

    async fn accept_transfer(&self, transfer_id: String) -> zbus::fdo::Result<()> {
        self.core.respond_to_transfer(transfer_id, true).map_err(|e| {
            error!("{}", e);
            zbus::fdo::Error::Failed(e.to_string())
        })
    }

    async fn reject_transfer(&self, transfer_id: String) -> zbus::fdo::Result<()> {
        self.core.respond_to_transfer(transfer_id, false).map_err(|e| {
            error!("{}", e);
            zbus::fdo::Error::Failed(e.to_string())
        })
    }

    #[zbus(signal)]
    pub async fn device_discovered(ctxt: &SignalContext<'_>, id: &str, name: &str, ip: &str) -> zbus::Result<()>;

    #[zbus(signal)]
    pub async fn transfer_requested(ctxt: &SignalContext<'_>, id: &str, device_name: &str, pin: &str) -> zbus::Result<()>;

    #[zbus(signal)]
    pub async fn transfer_progress(ctxt: &SignalContext<'_>, id: &str, state: &str, bytes_transferred: u64, total_bytes: u64) -> zbus::Result<()>;
}
