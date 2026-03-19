use anyhow::Result;
use log::info;
use rqs_lib::{
    channel::{ChannelAction, ChannelDirection, ChannelMessage},
    EndpointInfo, SendInfo, Visibility, RQS, OutboundPayload,
};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use tokio::sync::{broadcast, mpsc};

pub struct QuickShareCore {
    pub rqs: Arc<Mutex<RQS>>,
    pub sender_file: mpsc::Sender<SendInfo>,
}

impl QuickShareCore {
    pub async fn new() -> Result<(Self, broadcast::Receiver<ChannelMessage>)> {
        let download_dir = dirs::download_dir().unwrap_or_else(|| {
            dirs::home_dir().map(|h| h.join("Downloads")).unwrap_or_else(|| PathBuf::from("/tmp"))
        });
        info!("Incoming files will be saved to: {:?}", download_dir);

        let mut rqs = RQS::new(Visibility::Invisible, None, Some(download_dir));
        let msg_receiver = rqs.message_sender.subscribe();
        
        let (sender_file, _) = rqs.run().await?;
        
        let core = QuickShareCore {
            rqs: Arc::new(Mutex::new(rqs)),
            sender_file,
        };

        Ok((core, msg_receiver))
    }

    pub fn set_visibility(&self, visible: bool) -> Result<()> {
        let visibility = if visible {
            Visibility::Visible
        } else {
            Visibility::Invisible
        };
        
        let rqs_guard = self.rqs.lock().map_err(|e| anyhow::anyhow!("Failed to lock RQS: {}", e))?;
        let sender_guard = rqs_guard.visibility_sender.lock().map_err(|e| anyhow::anyhow!("Failed to lock visibility sender: {}", e))?;
        
        sender_guard.send(visibility).map_err(|e| anyhow::anyhow!("Failed to change visibility: {}", e))?;
        info!("Visibility changed to: {:?}", visibility);
        Ok(())
    }

    pub fn start_discovery(&self) -> Result<broadcast::Receiver<EndpointInfo>> {
        let mut rqs_guard = self.rqs.lock().map_err(|e| anyhow::anyhow!("Failed to lock RQS: {}", e))?;
        let (dch_sender, dch_receiver) = broadcast::channel::<EndpointInfo>(50);
        
        rqs_guard.discovery(dch_sender).map_err(|e| anyhow::anyhow!("Failed to start discovery: {}", e))?;
        info!("Started discovery for Quick Share devices");
        
        Ok(dch_receiver)
    }

    pub async fn send_files(&self, device_id: String, device_name: String, ip_addr: String, files: Vec<String>) -> Result<()> {
        info!("Request to send {} files to {}", files.len(), device_name);
        
        let send_info = SendInfo {
            id: device_id,
            name: device_name,
            addr: ip_addr,
            ob: OutboundPayload::Files(files),
        };

        self.sender_file.send(send_info).await.map_err(|e| anyhow::anyhow!("Failed to queue files: {}", e))?;
        Ok(())
    }

    pub fn respond_to_transfer(&self, transfer_id: String, accept: bool) -> Result<()> {
        info!("{} transfer {}", if accept { "Accepting" } else { "Rejecting" }, transfer_id);
        
        let rqs_guard = self.rqs.lock().map_err(|e| anyhow::anyhow!("Failed to lock RQS: {}", e))?;
        
        let action = if accept { ChannelAction::AcceptTransfer } else { ChannelAction::RejectTransfer };
        
        let msg = ChannelMessage {
            id: transfer_id,
            direction: ChannelDirection::FrontToLib,
            action: Some(action),
            rtype: None,
            state: None,
            meta: None,
        };

        rqs_guard.message_sender.send(msg).map_err(|e| anyhow::anyhow!("Failed to send transfer response: {}", e))?;
        Ok(())
    }
}
