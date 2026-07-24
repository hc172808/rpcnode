package core

import (
	"encoding/json"

	"github.com/gydschain/litenode/storage"
)

// openDB initialises the storage backend. On Replit we use in-memory storage;
// a disk-backed backend can be swapped in later without touching Chain.
func (c *Chain) openDB() error {
	c.db = storage.NewMemStorage()
	return nil
}

// loadFromDB replays persisted blocks into the in-memory chain state.
func (c *Chain) loadFromDB() error {
	if c.db == nil {
		return nil
	}
	it := c.db.Iterator([]byte("block:"))
	defer it.Release()
	for it.Next() {
		var b Block
		if err := json.Unmarshal(it.Value(), &b); err != nil {
			continue
		}
		if _, exists := c.byHash[b.Hash]; !exists {
			c.blocks = append(c.blocks, &b)
			c.byHash[b.Hash] = &b
			c.byNumber[b.Header.Number] = &b
			for _, tx := range b.Transactions {
				c.applyTx(tx)
			}
		}
	}
	return it.Error()
}

// Close releases the storage backend.
func (c *Chain) Close() {
	if c.db != nil {
		_ = c.db.Close()
		c.db = nil
	}
}

// persistBlock writes a block to the storage backend.
func (c *Chain) persistBlock(b *Block) {
	if c.db == nil {
		return
	}
	data, err := json.Marshal(b)
	if err != nil {
		return
	}
	key := []byte("block:" + b.Hash)
	_ = c.db.Put(key, data)
}
